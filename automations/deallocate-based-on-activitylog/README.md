# Deallocate VM based on Activity Log

A machine shut down from inside Windows or Linux is stopped, still allocated on a host, and
still billed for compute. This watches for exactly that event and deallocates the machine a few
minutes later. One alert rule, one Logic App, no schedule and no tags.

The same automation exists in three forms, all creating the same five resources:

| Form | Where |
|---|---|
| Bicep | this folder |
| ARM, behind a Deploy to Azure button | [simon-vedder/arm](https://github.com/simon-vedder/arm/tree/main/automations/deallocate-based-on-activitylog) |
| Terraform | [simon-vedder/terraform-azure](https://github.com/simon-vedder/terraform-azure/tree/main/automations/deallocate-based-on-activitylog) |

## Deploy

```bash
az deployment group create --resource-group rg-automations --template-file main.bicep
```

Give the alert rule about five minutes before you test it. A new activity-log rule is not live
the moment it exists.

**To deploy:** `Contributor` on the resource group, and `User Access Administrator` or `Owner`
on the subscription, because one role assignment lands there.

## What it creates

| Resource | Purpose |
|---|---|
| Activity-log alert `TriggerLogicAppViaHealthAlert` | subscription-wide: category Resource Health, resource type virtual machine, `properties.cause` = `UserInitiated` |
| Action group `TriggerLogicAppViaHealthAlert` | posts the common alert schema to the workflow's HTTP trigger |
| Logic App `DeallocateStoppedVM` | four variables from the payload, one condition, one call |
| API connection `azurerm_connection` | the Azure VM connector, set to authenticate as the managed identity |
| Role assignment at the subscription | `Desktop Virtualization Power On Off Contributor` for the workflow's identity |

## How it decides

Azure writes down **why** a machine stopped, and says it in different words for a guest shutdown
than for an API stop. That difference is the whole rule.

1. The guest powers off. Azure sets the machine to `PowerState/stopped` and leaves it allocated.
2. Within about a minute a Resource Health event lands with cause `UserInitiated` and the title
   *Stopped by user or process*. It arrives twice: an Activated entry with an empty description,
   then an Updated one carrying the sentence that matters.
3. The alert fires, the action group calls the workflow, and the workflow checks the description
   for **"or due to a guest activity from within the Virtual Machine"**. A stop from the portal
   or the CLI reads *as requested by an authorized user or process* and nothing more, so it is
   left alone.

Starts, stops and deallocations all trigger the workflow. The description check is what turns
everything but a guest shutdown into a no-op, so expect several runs per machine in the history
with one reaching the deallocate step.

## The identity

One built-in role at the subscription:
`Desktop Virtualization Power On Off Contributor` — read, start, power off and deallocate a
virtual machine. No write, no extensions, no run command, no login. The name is misleading and
the role is not: it is the narrowest built-in role that can deallocate a machine, and it has
nothing to do with AVD unless you point it at a host pool.

## What it holds

**No state.** No tag, no table, no list of machines. The workflow takes the machine, its resource
group and its subscription out of the alert payload, so it acts wherever the event came from.
The Logic App run history is the record.

## Verified

12 September 2026, against a Standard_B1s Ubuntu VM shut down from inside the guest:

| Run | Result |
|---|---|
| Bicep, guest shutdown | down at 11:52:16, deallocated by 11:55:09 |
| Terraform, guest shutdown | down at 12:31:50, deallocated by 12:35:04 |
| ARM through the button, guest shutdown | down at 12:44:24, deallocated by 13:00:25, with the alert pipeline delivering everything a quarter of an hour late that afternoon |
| `az vm stop`, no deallocate | left stopped, as intended |
| VM start, VM deallocate | each triggers a run; the condition is false and nothing is done |

That run found three defects in the templates as first published in June 2025: the Bicep API
connection was not configured for managed identity, the alert rule in Bicep and ARM filtered on a
field the Activity Log does not have, and both called the workflow's management URL instead of
the trigger's. All three are fixed.

## Do not use this for

- Machines whose dynamic public IP or ephemeral OS disk has to survive a shutdown. Deallocation
  releases the one and discards the other.
- Stops you make deliberately from the CLI or the portal. Those are left alone by design.
- Schedules, guards, a dry run or a record of what was decided. Use
  [VM Power Management](https://simonvedder.com/tools/vm-power-management/) instead.

## Read on

- [The write-up](https://simonvedder.com/deallocate-vm-based-on-activity-log/), how it was built
- [The tool page](https://simonvedder.com/tools/deallocate-on-activity-log/)
