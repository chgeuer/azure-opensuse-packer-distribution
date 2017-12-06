# Distribute images

## Download ISO image

```bash
export openSuseVersion=42.3
export imageLocation="https://download.opensuse.org/distribution/leap/${openSuseVersion}/iso/openSUSE-Leap-${openSuseVersion}-DVD-x86_64.iso"
curl --get --location --output "openSUSE-Leap-${openSuseVersion}-DVD-x86_64.iso" --url $imageLocation
```

## Build a vhdx file

### install packer, if needed

```bash
go get github.com/mitchellh/packer
```

### Use packer, to install and build openSUSE in a local Hyper-V installation

```cmd
set PACKER_LOG=1
packer build packer-hyper-v.json
```

- The installation is configured through the `http/autoinst.xml` file. The file stucture is defined in [AutoYaST documentation](https://doc.opensuse.org/projects/autoyast/).
- The `packer build` run creates a `.vhdx` file in `output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhdx`. 

### Convert `.vhdx` to fixed-size `.vhd`

```powershell
Convert-VHD –Path "output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhdx" -DestinationPath "output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhd" -VHDType Fixed
```

### Create target ingest storage account

```bash
managementSubscriptionId=724467b5-bee4-484b-bf13-d6a5505d2b51
demoPrefix=hecdemo
managementResourceGroup="${demoPrefix}management"
imageIngestDataCenter=westeurope
imageIngestStorageAccountName="${demoPrefix}imageingest"
imageIngestStorageContainerName="imagedistribution"
imageLocalFile="output-hyperv-iso/Virtual Hard Disks/packer-hyperv-iso.vhd"
imageBlobName="2017-12-06-opensuse-image.vhd"


az account set \
  --subscription $managementSubscriptionId

#
# Create the management resource group
#
az group create \
  --name "${managementResourceGroup}" \
  --location "${imageIngestDataCenter}"

#
# Create the storage account where images are uploaded to
#
az storage account create \
  --name "${demoPrefix}imageingest" \
  --resource-group "${managementResourceGroup}" \
  --location "${imageIngestDataCenter}" \
  --https-only true \
  --kind Storage \
  --sku Standard_RAGRS

#
# Fetch storage account key
#
imageIngestStorageAccountKey=$(az storage account keys list \
  --resource-group "${managementResourceGroup}" \
  --account-name "${imageIngestStorageAccountName}" \
  --query "[?contains(keyName,'key1')].[value]" \
  --o tsv)

#
# Create the storage container where images are uploaded
#
az storage container create \
  --account-name "${imageIngestStorageAccountName}" \
  --account-key  "${imageIngestStorageAccountKey}" \
  --name         "${imageIngestStorageContainerName}" \
  --public-access off

#
# Upload the image to the distribution point
#
az storage blob upload \
  --type page \
  --account-name   "${imageIngestStorageAccountName}" \
  --account-key    "${imageIngestStorageAccountKey}" \
  --container-name "${imageIngestStorageContainerName}" \
  --file "${imageLocalFile}" \
  --name "${imageBlobName}"
```

## links

- [Azure: Prepare a SLES or openSUSE virtual machine for Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/suse-create-upload-vhd)
