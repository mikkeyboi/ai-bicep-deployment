# Quickstart: 002 New Foundry

```pwsh
# 1. Validate
& "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd" `
    deployment sub validate `
    --location eastus2 `
    --template-file infra/main.bicep `
    --parameters infra/parameters/main.dev.bicepparam

# 2. What-if (expect: deletes for old hub/project + standalone OpenAI;
#    creates for Foundry account, project, model deployments).
& "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd" `
    deployment sub what-if `
    --location eastus2 `
    --template-file infra/main.bicep `
    --parameters infra/parameters/main.dev.bicepparam

# 3. Tear down legacy resources (one-shot, irreversible).
$rg = 'rg-aio-dev-eus2'
$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
& $az resource delete --resource-group $rg --name proj-aio-dev-eus2 `
    --resource-type Microsoft.MachineLearningServices/workspaces
& $az resource delete --resource-group $rg --name hub-aio-dev-eus2 `
    --resource-type Microsoft.MachineLearningServices/workspaces
& $az cognitiveservices account delete -g $rg -n oai-aio-dev-eus2-npnga
& $az cognitiveservices account purge -l eastus2 -g $rg -n oai-aio-dev-eus2-npnga

# 4. Deploy.
$stamp = (Get-Date).ToString('yyyyMMdd-HHmm')
& $az deployment sub create `
    --name "aio-dev-newfoundry-$stamp" `
    --location eastus2 `
    --template-file infra/main.bicep `
    --parameters infra/parameters/main.dev.bicepparam

# 5. Smoke check.
& $az cognitiveservices account show -g $rg -n <foundry-account-name>
& $az cognitiveservices account deployment list -g $rg -n <foundry-account-name>
& $az resource list -g $rg --resource-type Microsoft.CognitiveServices/accounts/projects
```
