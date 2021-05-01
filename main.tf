provider "aws" {
    region                  = "us-east-1"
    shared_credentials_file = "/home/at/.aws/credentials"
}

# Creating VPC
resource "aws_vpc" "website_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name    = "Nginx website VPC"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Getting information about available AZ
data "aws_availability_zones" "available" {}

# Creating public subnet us-east-1a
resource "aws_subnet" "public_us_east_1a" {
  vpc_id            = aws_vpc.website_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name    = "Public subnet us-east-1a"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Creating public subnet us-east-1b
resource "aws_subnet" "public_us_east_1b" {
  vpc_id            = aws_vpc.website_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name    = "Public subnet us-east-1b"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Creating internet gateway
resource "aws_internet_gateway" "website_vpc_igw" {
  vpc_id = aws_vpc.website_vpc.id

  tags = {
    Name = "Nginx website VPC internert gateway"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Creating route table
resource "aws_route_table" "website_vpc_public_rt" {
  vpc_id = aws_vpc.website_vpc.id

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.website_vpc_igw.id
  }

  tags = {
    Name    = "Public Subnets Route Table for Nginx website VPC"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Creating an association between a route table and a subnet us-east-1a
resource "aws_route_table_association" "Nginx_website_VPC_public_us_east_1a" {
    subnet_id      = aws_subnet.public_us_east_1a.id
    route_table_id = aws_route_table.website_vpc_public_rt.id
}

# Creating an association between a route table and a subnet us-east-1b
resource "aws_route_table_association" "Nginx_website_VPC_public_us_east_1b" {
    subnet_id      = aws_subnet.public_us_east_1b.id
    route_table_id = aws_route_table.website_vpc_public_rt.id
}

# Creating security group that allows inbound HTTP
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow inbound HTTP"
  vpc_id      = aws_vpc.website_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "Allow inbound HTTP security group"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Getting information about the latest Ubuntu-ami 
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

# Creating launch configuration
resource "aws_launch_configuration" "website_lc" {
  name_prefix                 = "linux_webserver_lc-"
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  security_groups             = [aws_security_group.allow_http.id]
  associate_public_ip_address = true
  user_data                   = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# Creating load balancer security group that allows inbound HTTP
resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow inbound HTTP to instances through Elastic Load Balancer"
  vpc_id      = aws_vpc.website_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "Allow inbound HTTP through ELB security group"
    Owner   = "Aleksandr Tolstov"
    Project = "DevOps"
  }
}

# Creating VPC elastic load balancer
resource "aws_elb" "website_elb" {
  name = "website-elb"
  security_groups = [
    aws_security_group.elb_http.id
  ]
  subnets = [
    aws_subnet.public_us_east_1a.id,
    aws_subnet.public_us_east_1b.id
  ]
  cross_zone_load_balancing = true

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }
}

# Creating autoscaling group
resource "aws_autoscaling_group" "website_asg" {
  name = "ASG using ${aws_launch_configuration.website_lc.name}"

  min_size             = 1
  desired_capacity     = 1
  max_size             = 2
  
  health_check_type    = "ELB"
  load_balancers = [
    aws_elb.website_elb.id
  ]

  launch_configuration = aws_launch_configuration.website_lc.name

  vpc_zone_identifier  = [
    aws_subnet.public_us_east_1a.id,
    aws_subnet.public_us_east_1b.id
  ]

  lifecycle {
    create_before_destroy = true
  }

  dynamic "tag" {
    for_each = {
      Name  = "Website created by ASG"
      Owner   = "Aleksandr Tolstov"
      Project = "DevOps"  
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

output "elb_dns_name" {
  value = aws_elb.website_elb.dns_name
}
