# Simulating outbound connectivity failures in E2E

This document shows one way to reproduce an outbound connectivity failure inside the AgentBaker E2E harness so you can validate that `provision.json` carries the detailed error text. The sample keeps the upstream artifacts untouched and relies on a scenario-local VM extension that temporarily blocks HTTPS egress before `vmssCSE` runs.

> The goal is to let the dedicated outbound curl probe inside `nodePrep` fail, so `record_outbound_command_failure` captures the curl exit code and `cse_start.sh` copies the explanation into `provision.json`.

## Scenario skeleton

Add a scenario similar to the one below to `e2e/scenario_test.go` (or create a helper that injects the same VM configuration mutator into an existing scenario):

```go
var ScenarioOutboundBlocker = Scenario{
    Description: "Ubuntu 22.04 node with outbound HTTPS blocked before CSE starts",
    Tags: Tags{
        Name: "Test_UbuntuOutboundBlocked",
        OS:   "ubuntu",
        Arch: "amd64",
    },
    Config: Config{
        Cluster:                       ClusterKubenet,
        VHD:                           config.ImageUbuntu2204Gen2AMD64,
        SkipDefaultValidation:         true,
        SkipSSHConnectivityValidation: true,
        VMConfigMutator: func(vmss *armcompute.VirtualMachineScaleSet) {
            const blockerName = "DropOutbound443"

            blockerScript := base64.StdEncoding.EncodeToString([]byte(`#!/bin/bash
set -euxo pipefail
# Override mcr.microsoft.com so curl never leaves the VM.
target_host="mcr.microsoft.com"
tmp_hosts="/etc/hosts.ab-outbound-blocker"
grep -v "${target_host}" /etc/hosts >"${tmp_hosts}" || true
printf "127.0.0.1 %s\\n" "${target_host}" >>"${tmp_hosts}"
mv "${tmp_hosts}" /etc/hosts
# Leave a breadcrumb for post-mortem validation.
printf 'ab-outbound-blocker installed\n' >/var/log/ab-outbound-blocker.log
`))

            blocker := &armcompute.VirtualMachineScaleSetExtension{
                Name: to.Ptr(blockerName),
                Properties: &armcompute.VirtualMachineScaleSetExtensionProperties{
                    Publisher:          to.Ptr("Microsoft.Azure.Extensions"),
                    Type:               to.Ptr("CustomScript"),
                    TypeHandlerVersion: to.Ptr("2.1"),
                    AutoUpgradeMinorVersion: to.Ptr(true),
                    Settings:           map[string]any{},
                    ProtectedSettings: map[string]any{
                        "commandToExecute": fmt.Sprintf(
                            "/bin/bash -c 'echo %s | base64 -d >/var/lib/%s.sh && chmod +x /var/lib/%s.sh && /var/lib/%s.sh'",
                            blockerScript, blockerName, blockerName, blockerName,
                        ),
                    },
                },
            }

            vmss.Properties = addVMExtensionToVMSS(vmss.Properties, blocker)

            // Ensure vmssCSE runs after the blocker finished so iptables rules are in place
            for _, ext := range vmss.Properties.VirtualMachineProfile.ExtensionProfile.Extensions {
                if ext != nil && ext.Name != nil && *ext.Name == "vmssCSE" {
                    ext.Properties.ProvisionAfterExtensions = append(
                        ext.Properties.ProvisionAfterExtensions,
                        to.Ptr(blockerName),
                    )
                }
            }
        },
        Validator: func(ctx context.Context, s *Scenario) {
            res, err := RunCommand(ctx, s, "sudo cat /var/log/azure/aks/provision.json")
            require.NoError(s.T, err)
            raw := strings.Join(toolkit.ToStringSlice(res.Value), "\n")
            require.Contains(s.T, raw, "Outbound connectivity check failed", "provision.json missing enriched text")
        },
    },
    AllowedCSEExitCodes: []string{"50"},
}
```

Key points:

1. **`VMConfigMutator` injects a short-lived Custom Script extension** that rewrites `/etc/hosts` so `mcr.microsoft.com` resolves to `127.0.0.1`, guaranteeing the outbound probe fails without touching the rest of the iptables configuration. The script is Base64 encoded so we can safely embed it inside the extension payload.
2. **`ProvisionAfterExtensions` on the stock `vmssCSE` extension** guarantees the blocker completes before the actual AgentBaker Custom Script starts.
3. **`SkipDefaultValidation`, `SkipSSHConnectivityValidation`, and `AllowedCSEExitCodes`** allow the scenario to keep running even though `vmssCSE` exits with code 50, so follow-up validators can still fetch logs.
4. **The validator fetches `/var/log/azure/aks/provision.json`** directly from the VMSS instance using `RunCommand` and asserts that the outbound failure text was propagated.

## Shell script reference

The script embedded above is intentionally minimal:

```bash
#!/bin/bash
set -euxo pipefail
target_host="mcr.microsoft.com"
tmp_hosts="/etc/hosts.ab-outbound-blocker"
grep -v "${target_host}" /etc/hosts >"${tmp_hosts}" || true
printf "127.0.0.1 %s\\n" "${target_host}" >>"${tmp_hosts}"
mv "${tmp_hosts}" /etc/hosts
printf 'ab-outbound-blocker installed\n' >/var/log/ab-outbound-blocker.log
```

You can tailor it to block only MCR’s current VIP ranges or to tear down the firewall rule after a delay if you want the node to eventually finish provisioning.

## Running the scenario

1. Export or place in `e2e/.env` the standard credentials plus:

   ```bash
   KEEP_VMSS=true
   TAGS_TO_RUN="name=Test_UbuntuOutboundBlocked"
   ```

2. From the repo root, run `./e2e/e2e-local.sh` or `go test -run Test_UbuntuOutboundBlocked -v ./e2e`.

3. Once the VM hits exit code 50, download the scenario’s log bundle (or call `RunCommand`) and inspect `/var/log/azure/aks/provision.json` to confirm the additional outbound failure line appears ahead of the `cluster-provision.log` tail.

This sample isolates the exact plumbing we added (scratch file → provision.json) without modifying upstream AgentBaker code or requiring fake registry endpoints.
