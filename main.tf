provider "aws" {
  region = "us-west-2"
  #access_key = "${var.aws_access_key}"
  #secret_key = "${var.aws_secret_key}"
}
terraform {
  backend "s3" {
    bucket = "ghaction-tfstate-bucket"
    key    = "terraform.tfstate"
    region = "us-west-2"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
variable "interfacename" {
  type = string
  default = "[Enter the corresponding Interface Name, not the IP address]"
  description = "eth0 will be used for setting by commcare-monolithic setup"
}


resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = "monolithic-test"
  }
}

resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "monolithic-test"
  }
}

resource "aws_network_interface" "foo" {
  subnet_id   = aws_subnet.my_subnet.id
  private_ips = ["172.16.10.100"]

  tags = {
    Name = "primary_network_interface"
  }
}
resource "aws_security_group" "foo" {
  name_prefix = "example-"
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
resource "aws_key_pair" "example" {
  key_name   = "ghaction-keypair"
  public_key = file("~/.ssh/id_rsa.pub")
  #public_key = file ("/optd/test/data")
}



resource "aws_instance" "foo" {
  ami           = "ami-0735c191cf914754d" # us-west-2
  instance_type = "t2.xlarge"

  key_name      =  aws_key_pair.example.key_name
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.foo.id]
 /* network_interface {
    network_interface_id = aws_network_interface.foo.id
    device_index         = 0
  } */
   tags = {
       Name = "gh-action-test"
     }
  credit_specification {
    cpu_credits = "unlimited"
  }
  root_block_device {
    volume_size = 40
    volume_type = "gp2"
  }
connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }
 
 provisioner "remote-exec" {
   when = destroy
      inline  = ["echo ${self.private_ip}"]
 }
 provisioner "remote-exec" {
    on_failure = continue
    inline = [
     "sudo apt -y update",
     "sudo sed -i '1s/^/\\$nrconf{restart} = \"a\"\\n/' /etc/needrestart/needrestart.conf",
     "sudo apt -y upgrade",
     "git clone https://github.com/dimagi/commcare-cloud",
     "cd commcare-cloud/quick_monolith_install",
     "sudo apt install -y python3.10-venv",
     "sudo apt install libffi-dev",
     "sudo apt-get install -y expect",
     "cp install-config.yml.sample install-config.yml",
     "sed -i 's/site_host: \"\"/site_host: \"monolithic\"/' install-config.yml",
     "sed -i 's/env_name: \"\"/env_name: \"monolithic\"/' install-config.yml",
     "sed -i 's/server_inventory_name: \"\"/server_inventory_name: \"hqserver1\"/' install-config.yml",
     "sed -i 's/server_host_name: \"\"/server_host_name: \"monolithic.example.com\"/' install-config.yml",
     "bash cchq-install.sh install-config.yml",
     "expect -c 'spawn bash cchq-install.sh install-config.yml; expect ${var.interfacename}; send \"eth0\\r\"; interact'",
     "set -e",
     "if bash cchq-install.sh install-config.yml; then",
     "  echo 'Installation completed successfully'",
     "else",
     "  echo 'Installation failed, running other-script.sh'",
     #"  bash other-script.sh",
     "fi"
    ]
  }
}
output "public_ip" {
  value = aws_instance.foo.public_ip
}
output "private_ip" {
  value = aws_instance.foo.private_ip
}

