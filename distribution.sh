#!/bin/bash

# function progress_to_percent {
#     IN=$1
#     arrIN=(${IN//\// })
#     cur=${arrIN[0]}
#     total=${arrIN[1]}
#     percent=$(( 100 * $cur / $total  ))
#     echo "${percent}"
# }  

subscription="chgeuer-work"
resourceGroup="copy"
SourceAccountName="copydiskssource"
SourceContainer="vhds"
SourceBlob="basevm20180416183515.vhd"
targetContainerName="ima"

az account set \
    --subscription "${subscription}"

declare -A StorageAccountNames=( 
   ["northeurope"]="copynortheeurope" 
   ["southeastasia"]="copysoutheastasia" 
   ["eastus2"]="copyeastus2" 
)

declare -A RegionTag=( 
   ["northeurope"]="datacenter1" 
   ["southeastasia"]="datacenter2" 
   ["eastus2"]="datacenter3" 
)


#
# Fetch storage account keys
#
SourceAccountKey=$(az storage account keys list \
       --resource-group "${resourceGroup}" \
       --account-name   "${SourceAccountName}" \
       --query          "[?contains(keyName,'key1')].[value]" \
       --o              tsv)

declare -A StorageAccountKeys
for regionname in ${!StorageAccountNames[@]} 
do 
   key=$(az storage account keys list \
       --resource-group "${resourceGroup}" \
       --account-name   "${StorageAccountNames[$regionname]}" \
       --query          "[?contains(keyName,'key1')].[value]" \
       --o              tsv)

   StorageAccountKeys[$regionname]="${key}"
done

#
# Create Storage Account Containers
#
for regionname in ${!StorageAccountNames[@]} 
do 
    created=$(az storage container create \
        --account-name "${StorageAccountNames[$regionname]}" \
        --account-key  "${StorageAccountKeys[$regionname]}" \
        --name         "${targetContainerName}" \
        --public-access off | \
        jq -r ".created")
 
    if [ "true" == $created ]; then
        echo "Created container ${StorageAccountNames[$regionname]}/${targetContainerName} in region ${regionname}"
    else
        echo "Container ${StorageAccountNames[$regionname]}/${targetContainerName} already existed in region ${regionname}"
    fi
done

#
# Trigger copy operations
#
declare -A CopyOperationIDs
for regionname in ${!StorageAccountNames[@]} 
do 
    copyOperationId=$(az storage blob copy start \
        --source-account-name   "${SourceAccountName}" \
        --source-account-key    "${SourceAccountKey}" \
        --source-container      "${SourceContainer}" \
        --source-blob           "${SourceBlob}" \
        --account-name          "${StorageAccountNames[$regionname]}" \
        --account-key           "${StorageAccountKeys[$regionname]}" \
        --destination-container "${targetContainerName}" \
        --destination-blob      "${SourceBlob}" | \
            jq -r ".id")

    CopyOperationIDs[$regionname]="${copyOperationId}"
done

while [ ${#CopyOperationIDs[@]} -gt 0 ]; do
    for regionname in ${!CopyOperationIDs[@]} 
    do 
        statusJson=$(az storage blob show \
            --account-name   "${StorageAccountNames[$regionname]}" \
            --account-key    "${StorageAccountKeys[$regionname]}" \
            --container-name "${targetContainerName}" \
            --name           "${SourceBlob}")
        
        status=$(echo $statusJson | jq -r ".properties.copy.status")
        progress=$(echo $statusJson | jq -r ".properties.copy.progress")

        dest="${StorageAccountNames[$regionname]}/${targetContainerName}/${SourceBlob}"
        if [ "success" == $status ]; then
            echo "Finished ${dest}, removing from list"
            unset CopyOperationIDs[$regionname]
        else
            # echo "Still working on ${dest}, $(progress_to_percent "${progress}")%"
            echo "Still working on ${dest}: ${progress}"
        fi
    done
done

echo "Finished all copy operations, copied the VHD to ${#StorageAccountNames[@]} regions"

for regionname in ${!StorageAccountNames[@]} 
do 
    vhdUrl=$(az storage blob url \
        --protocol "https" \
        --account-name   "${StorageAccountNames[$regionname]}" \
        --account-key    "${StorageAccountKeys[$regionname]}" \
        --container-name "${targetContainerName}" \
        --name           "${SourceBlob}" \
        --o tsv)

    imagename="${regionname}-${SourceBlob}"
    regionTag="${RegionTag[$regionname]}"
    
    echo "Creating image ${imagename} in ${regionname}, tagging it with datacenterID=${regionTag}. VHD is ${vhdUrl}"

    az image create \
        --name           "${imagename}" \
        --resource-group "${resourceGroup}" \
        --location       "${regionname}" \
        --source         "${vhdUrl}" \
        --os-type        Linux \
        --tags           "datacenterID=${regionTag}"
done
