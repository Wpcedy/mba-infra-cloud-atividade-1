terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {                     //plataforma que quero usar
      source  = "hashicorp/azurerm" //meio que a imagem que eu quero
      version = ">= 2.26 "          //versão desejada
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true //true - se fez o login antes se não false
  features {
      resource_group {
        prevent_deletion_if_contains_resources = false
      }
  }
}

//RESOURCE - a grande caixa que vai guardar tudo
resource "azurerm_resource_group" "rg_application" { //azurerm_resource_group = recurso que estou usando, rg_application = apelido para o recurso
  name     = "rg_application"
  location = var.location
}

//NETWORK
resource "azurerm_virtual_network" "vnet_application" {
  name                = "vnet_application"
  location            = azurerm_resource_group.rg_application.location //localização da caixa
  resource_group_name = azurerm_resource_group.rg_application.name     //nome da caixa
  address_space       = ["10.0.0.0/16"]
}

//SUB-NETWORK
resource "azurerm_subnet" "sub_application" {
  name                 = "sub_application"
  resource_group_name  = azurerm_resource_group.rg_application.name
  virtual_network_name = azurerm_virtual_network.vnet_application.name //nome da rede principal
  address_prefixes     = ["10.0.1.0/24"]
}

//IP CONFIG
resource "azurerm_public_ip" "ip_application" {
  name                = "ip_application"
  resource_group_name = azurerm_resource_group.rg_application.name
  location            = azurerm_resource_group.rg_application.location
  allocation_method   = "Static"
}

//FIREWALL
resource "azurerm_network_security_group" "nsg_application" {
  name                = "nsg_application"
  location            = azurerm_resource_group.rg_application.location
  resource_group_name = azurerm_resource_group.rg_application.name

  security_rule { //para o acesso ssh
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule { //para o acesso web
    name                       = "web"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

//NET-INTERFACE
resource "azurerm_network_interface" "nic_application" {
  name                = "nic_application"
  location            = azurerm_resource_group.rg_application.location
  resource_group_name = azurerm_resource_group.rg_application.name

  ip_configuration {
    name                          = "nic_ip_application"
    subnet_id                     = azurerm_subnet.sub_application.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip_application.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_application" {
  network_interface_id      = azurerm_network_interface.nic_application.id
  network_security_group_id = azurerm_network_security_group.nsg_application.id
}

//APACHE MACHINE
resource "azurerm_virtual_machine" "vm_application" {
  name                  = "vm_application"
  location              = azurerm_resource_group.rg_application.location
  resource_group_name   = azurerm_resource_group.rg_application.name
  network_interface_ids = [azurerm_network_interface.nic_application.id]
  vm_size               = "Standard_DC2s_v3"

  storage_image_reference { //Imagem da maquina
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16_04-lts-gen2"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "apacheMachine"
    admin_username = var.user
    admin_password = var.password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}

data "azurerm_public_ip" "ip_publico" { //estou pegando o ip publico do 'ip_application' e colocando no 'ip_publico'
  name                = azurerm_public_ip.ip_application.name
  resource_group_name = azurerm_resource_group.rg_application.name
}

resource "null_resource" "install_apache" { //instalar apache na maquina
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip_publico.ip_address
    user     = var.user
    password = var.password
  }

  provisioner "remote-exec" {//remote-exec = roda lá na maquina criada na azure
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2",
    ]
  }

  depends_on = [
    azurerm_virtual_machine.vm_application
  ]
}

# resource "null_resource" "upload_application" { //subir aplicação
#   connection {
#     type     = "ssh"
#     host     = data.azurerm_public_ip.ip_publico.ip_address
#     user     = var.user
#     password = var.password
#   }

#   provisioner "file" {//remote-exec = roda lá na maquina criada na azure
#     source = "application"//nome da pasta que contem a aplicação
#     destination = "/home/${var.user}"//var.user é o nome do usuario obrigatoriamente
#   }

#   depends_on = [
#     azurerm_virtual_machine.vm_application
#   ]
# }
