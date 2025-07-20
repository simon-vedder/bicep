# 💠 Azure Bicep Templates Collection

This repository contains a collection of Azure Bicep templates and related automation scripts that I use across various cloud projects. These templates aim to simplify and standardize infrastructure deployments on Azure with the declarative and modular Bicep language.

> 🛠️ Some templates are production-ready, while others serve as references or experiments for learning and prototyping.

---

## 📁 Repository Structure

_Still evolving, but generally organized as follows:_

```plaintext
bicep/
├── automations     #Automations like LogicApps etc.

```

## 🚀 How to Use

Deploy a Bicep template using the Azure CLI:
```
az deployment group create \
  --resource-group <your-resource-group> \
  --template-file ./main/template.bicep \
  --parameters ./parameters/parameters.json
```
  You can also compile Bicep files to ARM JSON templates with:
  ```
  az bicep build --file ./main/template.bicep
  ```