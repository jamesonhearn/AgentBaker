package main

// Some options are intentionally non-configurable to avoid customization by users
// it will help us to avoid introducing any breaking changes in the future.
const (
	logPath                           = "/var/log/azure/aks-node-controller.log"
	provisionJSONFilePath             = "/var/log/azure/aks/provision.json"
	provisionCompleteFilePath         = "/opt/azure/containers/provision.complete"
	clusterProvisionLogPath           = "/var/log/azure/cluster-provision.log"
	outboundCommandErrorMessagePath   = "/var/log/azure/aks/outbound-command-error-message"
	outboundConnectivityErrorExitCode = "50" // mirrors ERR_OUTBOUND_CONN_FAIL in shell helpers
)
