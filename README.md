# Distribute images

The walktrough describes how to distribute locally (on-prem) created VM images to one or more Azure subscriptions and data centers.

- The production VMs will use 'managed disks', therefore we need 'managed images' in the target subscriptions and data centers.
- For this sample, I locally create VM images (VHD files) using Hashicorp packer against Hyper-V. The local OS to be installed is openSUSE.
- Some scripts below are designed to be executed on a Windows host, particularly
  - Running `packer build` against Hyper-V
  - Running the `Convert-VHD` Commandlet, to convert the dynamic-size `.vhdx` file in a static-size `.vhd` file.
- All other commands can be executed on Windows, Windows Subsystem for Linux, Linux or MacOS X, as long as the `az` command line utility is installed.

![Image flow](img/img01.png?raw=true "Image flow")

## Build a VHD locally

In order to have a VHD I can distribute, I used packer on Hyper-V:

### Download ISO image

```bash
export openSuseVersion=42.3
export imageLocation="https://download.opensuse.org/distribution/leap/${openSuseVersion}/iso/openSUSE-Leap-${openSuseVersion}-DVD-x86_64.iso"
curl --get --location --output "openSUSE-Leap-${openSuseVersion}-DVD-x86_64.iso" --url $imageLocation
```

### install packer, if needed

```bash
go get github.com/mitchellh/packer
```

### Use packer, to install and build openSUSE in a local Hyper-V installation

```cmd
REM turn on packer logging
set PACKER_LOG=1

REM run packer against local Hyper-V
packer build packer-hyper-v.json
```

- The installation is configured through the `http/autoinst.xml` file. The file stucture is defined in [AutoYaST documentation](https://doc.opensuse.org/projects/autoyast/).
- The `packer build` run creates a `.vhdx` file in `output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhdx`.

### Convert `.vhdx` to fixed-size `.vhd`

```powershell
Convert-VHD `
  –Path "output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhdx" `
  -DestinationPath "output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhd" `
  -VHDType Fixed
```

## Upload and distribute the existing VHD from our build server to Azure

### Variables we need

```bash
export managementSubscriptionId="724467b5-bee4-484b-bf13-d6a5505d2b51"
export demoPrefix="hecdemo"
export managementResourceGroup="${demoPrefix}management"
export imageIngestDataCenter="westeurope"
export imageIngestStorageAccountName="${demoPrefix}imageingest"
export imageIngestStorageContainerName="imagedistribution"
export imageLocalFile="output-hyperv-iso/Virtual Hard Disks/packer-hyperv-iso.vhd"
export imageBlobName="2017-12-06-opensuse-image.vhd"

export productionSubscriptionId="706df49f-998b-40ec-aed3-7f0ce9c67759"
export productionDataCenter="northeurope"
export productionImageResourceGroup="${demoPrefix}production"
export productionImageIngestStorageAccountName="${demoPrefix}prodimages"
```

### Select the management subscription

```bash
az account set \
  --subscription $managementSubscriptionId
```

### Create the management resource group

```bash
az group create \
  --name "${managementResourceGroup}" \
  --location "${imageIngestDataCenter}"
```

### Create the storage account where images are uploaded to

```bash
az storage account create \
  --name           "${imageIngestStorageAccountName}" \
  --resource-group "${managementResourceGroup}" \
  --location       "${imageIngestDataCenter}" \
  --https-only     true \
  --kind           Storage \
  --sku            Standard_RAGRS
```

### Fetch storage account key

```bash
export imageIngestStorageAccountKey=$(az storage account keys list \
  --resource-group "${managementResourceGroup}" \
  --account-name   "${imageIngestStorageAccountName}" \
  --query          "[?contains(keyName,'key1')].[value]" \
  --o              tsv)
```

### Create the storage container where images are uploaded

```bash
az storage container create \
  --account-name "${imageIngestStorageAccountName}" \
  --account-key  "${imageIngestStorageAccountKey}" \
  --name         "${imageIngestStorageContainerName}" \
  --public-access off
```

### Upload the image to the distribution point

```bash
az storage blob upload \
  --type           page \
  --account-name   "${imageIngestStorageAccountName}" \
  --account-key    "${imageIngestStorageAccountKey}" \
  --container-name "${imageIngestStorageContainerName}" \
  --file           "${imageLocalFile}" \
  --name           "${imageBlobName}"
```

### Select the production subscription

```bash
az account set \
  --subscription $productionSubscriptionId
```

### Create the production image resource group

```bash
az group create \
  --name "${productionImageResourceGroup}" \
  --location "${productionDataCenter}"
```

### Create the production image storage account where images are copied to

```bash
az storage account create \
  --name           "${productionImageIngestStorageAccountName}" \
  --resource-group "${productionImageResourceGroup}" \
  --location       "${productionDataCenter}" \
  --https-only     true \
  --kind           Storage \
  --sku            Premium_LRS
```

### Fetch storage account key for the production storage account

```bash
export productionImageIngestStorageAccountKey=$(az storage account keys list \
  --resource-group "${productionImageResourceGroup}" \
  --account-name   "${productionImageIngestStorageAccountName}" \
  --query          "[?contains(keyName,'key1')].[value]" \
  --o tsv)
```

### Create the storage container where images are copied to

```bash
az storage container create \
  --account-name "${productionImageIngestStorageAccountName}" \
  --account-key  "${productionImageIngestStorageAccountKey}" \
  --name         "${imageIngestStorageContainerName}" \
  --public-access off
```

### Trigger the copy operation

- [`az storage blob copy start`](https://docs.microsoft.com/en-us/cli/azure/storage/blob/copy?view=azure-cli-latest#az_storage_blob_copy_start)

```bash
az storage blob copy start \
  --source-account-name   "${imageIngestStorageAccountName}" \
  --source-account-key    "${imageIngestStorageAccountKey}" \
  --source-container      "${imageIngestStorageContainerName}" \
  --source-blob           "${imageBlobName}" \
  --account-name          "${productionImageIngestStorageAccountName}" \
  --account-key           "${productionImageIngestStorageAccountKey}" \
  --destination-container "${imageIngestStorageContainerName}" \
  --destination-blob      "${imageBlobName}"
```

### Track the copy status

```bash
statusJson=$(az storage blob show \
  --account-name   "${productionImageIngestStorageAccountName}" \
  --account-key    "${productionImageIngestStorageAccountKey}" \
  --container-name "${imageIngestStorageContainerName}" \
  --name           "${imageBlobName}")

echo $statusJson | jq ".properties.copy.status"
echo $statusJson | jq ".properties.copy.progress"
```

### Create a managed image in the production subscription

```bash
productionImageIngestUrl=$(az storage blob url \
  --protocol "https" \
  --account-name   "${productionImageIngestStorageAccountName}" \
  --account-key    "${productionImageIngestStorageAccountKey}" \
  --container-name "${imageIngestStorageContainerName}" \
  --name           "${imageBlobName}" \
  --o tsv)

az image create \
  --name           "${imageBlobName}" \
  --resource-group "${productionImageResourceGroup}" \
  --location       "${productionDataCenter}" \
  --source         "${productionImageIngestUrl}" \
  --os-type        Linux
```

## links

- [Azure: Prepare a SLES or openSUSE virtual machine for Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/suse-create-upload-vhd)
