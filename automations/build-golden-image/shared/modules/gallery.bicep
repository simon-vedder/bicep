@description('Azure region for the gallery.')
param location string

@description('CAF name prefix.')
param namePrefix string

param tags object = {}

param enableWindowsServer2022 bool = true
param enableWindowsServer2025 bool = true
param enableWindows11MultiSession bool = true
param enableWindows11SingleSession bool = true

param enableUbuntu2204 bool = false
param enableUbuntu2404 bool = false
param enableRhel8 bool = false
param enableRhel9 bool = false

// Gallery name: alphanumeric, underscores, dots only — NO hyphens
var galleryName = 'gal_${replace(namePrefix, '-', '_')}'

resource gallery 'Microsoft.Compute/galleries@2023-07-03' = {
  name: galleryName
  location: location
  tags: tags
  properties: {
    description: 'Golden Image Gallery — ${namePrefix}'
  }
}

resource imgDefWS2022 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableWindowsServer2022) {
  parent: gallery
  name: 'imgdef-${namePrefix}-ws2022'
  location: location
  tags: tags
  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'WindowsServer'
      sku: '2022'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefWS2025 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableWindowsServer2025) {
  parent: gallery
  name: 'imgdef-${namePrefix}-ws2025'
  location: location
  tags: tags
  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'WindowsServer'
      sku: '2025'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefWin11MS 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableWindows11MultiSession) {
  parent: gallery
  name: 'imgdef-${namePrefix}-win11-ms'
  location: location
  tags: tags
  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'Windows11'
      sku: 'multisession'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefWin11SS 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableWindows11SingleSession) {
  parent: gallery
  name: 'imgdef-${namePrefix}-win11-ss'
  location: location
  tags: tags
  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'Windows11'
      sku: 'singlesession'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefUbuntu2204 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableUbuntu2204) {
  parent: gallery
  name: 'imgdef-${namePrefix}-ubuntu2204'
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'Ubuntu'
      sku: '2204'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefUbuntu2404 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableUbuntu2404) {
  parent: gallery
  name: 'imgdef-${namePrefix}-ubuntu2404'
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'Ubuntu'
      sku: '2404'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefRhel8 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableRhel8) {
  parent: gallery
  name: 'imgdef-${namePrefix}-rhel8'
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'RHEL'
      sku: '8'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

resource imgDefRhel9 'Microsoft.Compute/galleries/images@2023-07-03' = if (enableRhel9) {
  parent: gallery
  name: 'imgdef-${namePrefix}-rhel9'
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    identifier: {
      publisher: 'GoldenImage'
      offer: 'RHEL'
      sku: '9'
    }
    recommended: {
      vCPUs: { min: 2, max: 128 }
      memory: { min: 4, max: 512 }
    }
  }
}

output galleryId string = gallery.id
output galleryName string = gallery.name
