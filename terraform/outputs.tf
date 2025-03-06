# terraform/outputs.tf
output "vm_public_ips" {
 value = [for pip in azurerm_public_ip.pip : pip.ip_address]
 description = "The public IP addresses of the VMs"
}
output "vm_access_details" {
 value = {
 for idx, pip in azurerm_public_ip.pip : "vm-${idx + 1}" => {
 public_ip = pip.ip_address
 grafana_url = "http://${pip.ip_address}:3000"
 prometheus_url = "http://${pip.ip_address}:9090"
 }
 }
 description = "Access details for the VMs including Grafana and Prometheus URLs"
}
