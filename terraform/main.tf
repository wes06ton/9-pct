# BLOCK: Resource Group
# PURPOSE: Create the main resource group for production VMs
resource "azurerm_resource_group" "rg" {
 name = "prod-vms-rg"
 location = "East US"
 
 lifecycle {
 prevent_destroy = true
 ignore_changes = [tags]
 }
}
# BLOCK: Virtual Network
# PURPOSE: Create the virtual network for VM networking
resource "azurerm_virtual_network" "vnet" {
 name = "prod-vnet"
 address_space = ["10.0.0.0/16"]
 location = azurerm_resource_group.rg.location
 resource_group_name = azurerm_resource_group.rg.name
}
# BLOCK: Subnet
# PURPOSE: Create subnet for VM placement
resource "azurerm_subnet" "subnet" {
 name = "prod-subnet"
 resource_group_name = azurerm_resource_group.rg.name
 virtual_network_name = azurerm_virtual_network.vnet.name
 address_prefixes = ["10.0.1.0/24"]
}
# BLOCK: Network Security Group
# PURPOSE: Define security rules for VM access
resource "azurerm_network_security_group" "nsg" {
 name = "prod-nsg"
 location = azurerm_resource_group.rg.location
 resource_group_name = azurerm_resource_group.rg.name
 security_rule {
 name = "AllowSSH"
 priority = 1001
 direction = "Inbound"
 access = "Allow"
 protocol = "Tcp"
 source_port_range = "*"
 destination_port_range = "22"
 source_address_prefix = "*"
 destination_address_prefix = "*"
 }
 security_rule {
 name = "AllowGrafana"
 priority = 1002
 direction = "Inbound"
 access = "Allow"
 protocol = "Tcp"
 source_port_range = "*"
 destination_port_range = "3000"
 source_address_prefix = "*"
 destination_address_prefix = "*"
 }
 security_rule {
 name = "AllowPrometheus"
 priority = 1003
 direction = "Inbound"
 access = "Allow"
 protocol = "Tcp"
 source_port_range = "*"
 destination_port_range = "9090"
 source_address_prefix = "*"
 destination_address_prefix = "*"
 }
}
# BLOCK: Public IP Addresses
# PURPOSE: Create public IPs for VM access
resource "azurerm_public_ip" "pip" {
 count = 3
 name = "pip-${count.index + 1}"
 location = azurerm_resource_group.rg.location
 resource_group_name = azurerm_resource_group.rg.name
 allocation_method = "Static"
 sku = "Standard"
}
# BLOCK: Network Interfaces
# PURPOSE: Create NICs for VM network connectivity
resource "azurerm_network_interface" "nic" {
 count = 3
 name = "nic-${count.index + 1}"
 location = azurerm_resource_group.rg.location
 resource_group_name = azurerm_resource_group.rg.name
 ip_configuration {
 name = "ipconfig1"
 subnet_id = azurerm_subnet.subnet.id
 private_ip_address_allocation = "Dynamic"
 public_ip_address_id = azurerm_public_ip.pip[count.index].id
 }
 depends_on = [
 azurerm_public_ip.pip,
 azurerm_subnet.subnet
 ]
}
# BLOCK: NSG Associations
# PURPOSE: Associate NSG with subnet and NICs
resource "azurerm_subnet_network_security_group_association"
"subnet_nsg_association" {
 subnet_id = azurerm_subnet.subnet.id
 network_security_group_id = azurerm_network_security_group.nsg.id
}
resource "azurerm_network_interface_security_group_association"
"nic_nsg_association" {
 count = 3
 network_interface_id = azurerm_network_interface.nic[count.index].id
 network_security_group_id = azurerm_network_security_group.nsg.id
}
# BLOCK: Virtual Machines
# PURPOSE: Create Linux VMs with monitoring capabilities
resource "azurerm_linux_virtual_machine" "vm" {
 count = 3
 name = "node${count.index + 1}"
 resource_group_name = azurerm_resource_group.rg.name
 location = azurerm_resource_group.rg.location
 size = "Standard_B2s"
 admin_username = "adminuser"
 network_interface_ids = [azurerm_network_interface.nic[count.index].id]
 admin_ssh_key {
 username = "adminuser"
 public_key = file("~/.ssh/id_rsa.pub")
 }
 os_disk {
 caching = "ReadWrite"
 storage_account_type = "Standard_LRS"
 disk_size_gb = 30
 }
 source_image_reference {
 publisher = "Canonical"
 offer = "0001-com-ubuntu-server-jammy"
 sku = "22_04-lts-gen2"
 version = "latest"
 }
 custom_data = base64encode(data.template_file.cloud_init.rendered)
 depends_on = [
 azurerm_network_interface.nic,
 azurerm_public_ip.pip,
 azurerm_network_interface_security_group_association.nic_nsg_association
 ]
}
# BLOCK: Cloud-Init Template
# PURPOSE: Configure VM initialization
data "template_file" "cloud_init" {
 template = file("${path.module}/cloud-init.yaml")
}
# BLOCK: Monitoring - CPU Alerts
# PURPOSE: Configure CPU usage alerts
resource "azurerm_monitor_metric_alert" "cpu_alert" {
 count = 3
 name = "high-cpu-alert-${count.index + 1}"
 resource_group_name = azurerm_resource_group.rg.name
 scopes = [azurerm_linux_virtual_machine.vm[count.index].id]
 description = "Alert when CPU usage exceeds 90% for 5 minutes"
 frequency = "PT1M"
 window_size = "PT5M"
 criteria {
 metric_namespace = "Microsoft.Compute/virtualMachines"
 metric_name = "Percentage CPU"
 aggregation = "Average"
 operator = "GreaterThan"
 threshold = 90
 }
 action {
 action_group_id = azurerm_monitor_action_group.email_action_group.id
 }
}
# BLOCK: Monitoring - Memory Alerts
# PURPOSE: Configure memory usage alerts
resource "azurerm_monitor_metric_alert" "memory_alert" {
 count = 3
 name = "high-memory-alert-${count.index + 1}"
 resource_group_name = azurerm_resource_group.rg.name
 scopes = [azurerm_linux_virtual_machine.vm[count.index].id]
 description = "Alert when memory usage exceeds 85% for 5 minutes"
 frequency = "PT1M"
 window_size = "PT5M"
 criteria {
 metric_namespace = "Microsoft.Compute/virtualMachines"
 metric_name = "Available Memory Bytes"
 aggregation = "Average"
 operator = "LessThan"
 threshold = (0.15 * (30 * 1024 * 1024 * 1024))
 }
 action {
 action_group_id = azurerm_monitor_action_group.email_action_group.id
 }
}
# BLOCK: Monitoring - Action Group
# PURPOSE: Configure email alerts
resource "azurerm_monitor_action_group" "email_action_group" {
 name = "email-action-group"
 resource_group_name = azurerm_resource_group.rg.name
 short_name = "EmailAlerts"
 email_receiver {
 name = "email-alert"
 email_address = "loladevops@gmail.com"
 use_common_alert_schema = true
 }
}
