terraform {
  backend "s3" {
    encrypt = "true"
  }
}

provider "aws" {}

# https://www.andreagrandi.it/2017/08/25/getting-latest-ubuntu-ami-with-terraform/
data "aws_ami" "ubuntu" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["099720109477"] # Canonical
}

data "aws_vpc" "vpc" {
    filter {
        name   = "tag:Name"
        values = ["${var.vpc_name}"]
    }
}

data "aws_subnet" "public" {
  filter {
      name   = "tag:Name"
      values = ["${var.subnet_name}"]
  }
  vpc_id = "${data.aws_vpc.vpc.id}"
}

data "aws_security_group" "ssh_in" {
  filter {
      name   = "group-name"
      values = ["${var.ssh_in_secgroup}"]
  }
  vpc_id = "${data.aws_vpc.vpc.id}"
}

data "aws_security_group" "egress" {
  filter {
      name   = "group-name"
      values = ["${var.egress_secgroup}"]
  }
  vpc_id = "${data.aws_vpc.vpc.id}"
}



resource "aws_iam_role" "role" {
  name = "${var.vm_name}-${var.vpc_name}-public_role"
  path = "/"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    tag-key = "${var.vpc_name}-public"
  }
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.vm_name}-${var.vpc_name}-public_instance-profile"
  role = "${aws_iam_role.role.name}"
}


resource "aws_iam_policy_attachment" "profile-attach" {
  count      = "${length(var.policies)}"
  name       = "${var.vm_name}-${var.vpc_name}-public-${count.index}"
  roles      = ["${aws_iam_role.role.name}"]
  policy_arn = "${element(var.policies,count.index)}"
}


resource "aws_instance" "cluster" {
  ami                    = "${var.ami == "" ? data.aws_ami.ubuntu.id : var.ami}"
  instance_type          = "${var.instance_type}"
  monitoring             = false
  vpc_security_group_ids = ["${data.aws_security_group.ssh_in.id}", "${data.aws_security_group.egress.id}"]
  subnet_id              = "${data.aws_subnet.public.id}"
  iam_instance_profile   = "${aws_iam_instance_profile.profile.name}"
  root_block_device {
    volume_size = "${var.volume_size}"
    encrypted = true
  }

  user_data = <<EOF
#!/bin/bash 

(
  if [[ ! -f /home/ubuntu/.ssh/authorized_keys ]]; then
    mkdir -p /home/ubuntu/.ssh/authorized_keys
    chown ubuntu: /home/ubuntu/.ssh/authorized_keys
    chmod 0600 /home/ubuntu/.ssh/authorized_keys
  fi
  cat - >> /home/ubuntu/.ssh/authorized_keys <<EOM
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDiVYoa9i91YL17xWF5kXpYh+PPTriZMAwiJWKkEtMJvyFWGv620FmGM+PczcQN47xJJQrvXOGtt/n+tW1DP87w2rTPuvsROc4pgB7ztj1EkFC9VkeaJbW/FmWxrw2z9CTHGBoxpBgfDDLsFzi91U2dfWxRCBt639sLBfJxHFo717Xg7L7PdFmFiowgGnqfwUOJf3Rk8OixnhEA5nhdihg5gJwCVOKty8Qx73fuSOAJwKntcsqtFCaIvoj2nOjqUOrs++HG6+Fe8tGLdS67/tvvgW445Ik5JZGMpa9y0hJxmZj1ypsZv/6cZi2ohLEBCngJO6d/zfDzP48Beddv6HtL rarya_id_rsa
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDBFbx4eZLZEOTUc4d9kP8B2fg3HPA8phqJ7FKpykg87w300H8uTsupBPggxoPMPnpCKpG4aYqgKC5aHzv2TwiHyMnDN7CEtBBBDglWJpBFCheU73dDl66z/vny5tRHWs9utQNzEBPLxSqsGgZmmN8TtIxrMKZ9eX4/1d7o+8msikCYrKr170x0zXtSx5UcWj4yK1al5ZcZieZ4KVWk9/nPkD/k7Sa6JM1QxAVZObK/Y9oA6fjEFuRGdyUMxYx3hyR8ErNCM7kMf8Yn78ycNoKB5CDlLsVpPLcQlqALnBAg1XAowLduCCuOo8HlenM7TQqohB0DO9MCDyZPoiy0kieMBLBcaC7xikBXPDoV9lxgvJf1zbEdQVfWllsb1dNsuYNyMfwYRK+PttC/W37oJT64HJVWJ1O3cl63W69V1gDGUnjfayLjvbyo9llkqJetprfLhu2PfSDJ5jBlnKYnEj2+fZQb8pUrgyVOrhZJ3aKJAC3c665avfEFRDO3EV/cStzoAnHVYVpbR/EXyufYTh7Uvkej8l7g/CeQzxTq+0UovNjRA8UEXGaMWaLq1zZycc6Dx/m7HcZuNFdamM3eGWV+ZFPVBZhXHwZ1Ysq2mpBEYoMcKdoHe3EvFu3eKyrIzaqCLT5LQPfaPJaOistXBJNxDqL6vUhAtETmM5UjKGKZaQ== emalinowski@uchicago.edu
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKJR5N5VIU9qdSfCtlskzuQ7A5kNn8YPeXsoKq0HhYZSd4Aq+7gZ0tY0dFUKtXLpJsQVDTflINc7sLDDXNp3icuSMmxOeNgvBfi8WnzBxcATh3uqidPqE0hcnhVQbpsza1zk8jkOB2o8FfBdDTOSbgPESv/1dnGApfkZj96axERUCMzyyUSEmif2moWJaVv2Iv7O+xjQqIZcMXiAo5BCnTCFFKGVOphy65cOsbcE02tEloiZ3lMAPMamZGV7SMQiD3BusncnVctn/E1vDqeozItgDrTdajKqtW0Mt6JFONVFobzxS8AsqFwaHiikOZhKq2LoqgvbXZvNWH2zRELezP jawadq@Jawads-MacBook-Air.local
EOM
)
(
  export DEBIAN_FRONTEND=noninteractive
    
  if which hostnamectl > /dev/null; then
    hostnamectl set-hostname 'lab${count.index}'
  fi
  mkdir -p -m 0755 /var/lib/gen3
  cd /var/lib/gen3
  if ! which git > /dev/null; then
    apt update
    apt install git -y
  fi
  git clone https://github.com/uc-cdis/cloud-automation.git 
  cd ./cloud-automation
  cat ./files/authorized_keys/ops_team | tee -a /home/ubuntu/.ssh/authorized_keys

  if [[ ! -d ./Chef ]]; then
    # until the code gets merged
    git checkout chore/labvm
  fi

  cd ./Chef
  bash ./installClient.sh
  # hopefully chef-client is ready to run now
  cd ./repo
  /bin/rm -rf nodes
  # add -l debug for more verbose logging
  chef-client --chef-license accept --local-mode --node-name littlenode --override-runlist 'role[devbox]'
) 2>&1 | tee /var/log/gen3boot.log
  EOF
  
  lifecycle {
    # Due to several known issues in Terraform AWS provider related to arguments of aws_instance:
    # (eg, https://github.com/terraform-providers/terraform-provider-aws/issues/2036)
    # we have to ignore changes in the following arguments
    ignore_changes = ["private_ip", "root_block_device", "ebs_block_device", "user_data"]
  }
  tags = {
    Name        = "${var.vm_name}-${var.vpc_name}-public"
    Terraform   = "true"
    Environment = "${var.vpc_name}"
  }
}

resource "aws_eip" "ips" {
  instance = "${aws_instance.cluster.id}"
  vpc      = true
}

