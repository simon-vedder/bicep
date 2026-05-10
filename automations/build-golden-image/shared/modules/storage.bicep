@description('Azure region.')
param location string

@description('CAF name prefix.')
param namePrefix string

@description('Principal ID of the AIB UAMI — granted Storage Blob Data Reader.')
param aibIdentityPrincipalId string

@description('GitHub raw base URL to download scripts from during deployment. Example: https://raw.githubusercontent.com/org/repo/branch/path/scripts')
param scriptSourceBaseUrl string

@description('List of script file names to download from source and upload to blob storage.')
param scriptFileNames array = ['windows-updates.ps1', 'install-agents.ps1', 'avd-optimizations.ps1', 'security-hardening.ps1']

@description('Optional second base URL for scripts from a different OS path (e.g. Linux scripts in a combined deployment).')
param secondaryScriptSourceBaseUrl string = ''

@description('Script file names to download from the secondary base URL.')
param secondaryScriptFileNames array = []

param tags object = {}

// Storage account name: 3-24 chars, lowercase alphanumeric only
// Fixed prefix 'stgib' (5 chars) guarantees Bicep type-checker sees min length >= 3
var storageAccountName = toLower(take('stgib${replace(replace(namePrefix, '-', ''), '_', '')}', 24))

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource scriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'scripts'
  properties: {
    publicAccess: 'None'
  }
}

// ── AIB UAMI — Storage Blob Data Reader (pull scripts during image build) ─────

var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource aibStorageRa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aibIdentityPrincipalId, storageBlobDataReaderRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalId: aibIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ── Deployment script UAMI — Storage Blob Data Contributor (upload scripts) ──

resource dsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-${namePrefix}-ds'
  location: location
  tags: tags
}

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource dsStorageRa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, dsIdentity.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: dsIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Deployment script — downloads scripts from GitHub, uploads to blob ────────
// Runs once at deploy time inside a temporary ACI container (~2 min, ~€0.01).
// Re-runs automatically if scriptSourceBaseUrl changes (forceUpdateTag drives this).

resource uploadScripts 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'ds-${namePrefix}-upload-scripts'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${dsIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.52.0'
    retentionInterval: 'PT1H'
    timeout: 'PT10M'
    forceUpdateTag: '${scriptSourceBaseUrl}|${secondaryScriptSourceBaseUrl}'
    environmentVariables: [
      { name: 'STORAGE_ACCOUNT', value: storageAccount.name }
      { name: 'SCRIPT_BASE_URL', value: scriptSourceBaseUrl }
      { name: 'SCRIPT_FILE_NAMES', value: join(scriptFileNames, ' ') }
      { name: 'SECONDARY_SCRIPT_BASE_URL', value: secondaryScriptSourceBaseUrl }
      { name: 'SECONDARY_SCRIPT_FILE_NAMES', value: join(secondaryScriptFileNames, ' ') }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e
      upload_script() {
        local base_url="$1" script="$2"
        echo "Downloading ${script}..."
        curl -sLf "${base_url}/${script}" -o "/tmp/${script}" || { echo "Failed to download ${script}"; exit 1; }
        echo "Uploading ${script}..."
        az storage blob upload \
          --account-name "${STORAGE_ACCOUNT}" \
          --container-name "scripts" \
          --name "${script}" \
          --file "/tmp/${script}" \
          --auth-mode login \
          --overwrite true
      }
      IFS=' ' read -ra SCRIPTS <<< "$SCRIPT_FILE_NAMES"
      for script in "${SCRIPTS[@]}"; do upload_script "$SCRIPT_BASE_URL" "$script"; done
      if [ -n "${SECONDARY_SCRIPT_BASE_URL}" ]; then
        IFS=' ' read -ra SEC_SCRIPTS <<< "$SECONDARY_SCRIPT_FILE_NAMES"
        for script in "${SEC_SCRIPTS[@]}"; do upload_script "$SECONDARY_SCRIPT_BASE_URL" "$script"; done
      fi
      echo "All scripts uploaded successfully."
    '''
  }
  dependsOn: [scriptsContainer, dsStorageRa]
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output scriptsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}scripts'
