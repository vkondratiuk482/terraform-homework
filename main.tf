terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-2"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC and Security Groups setup

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name = "main-vpc"
  cidr = "10.0.0.0/16"

  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_security_group" "kyiv_instance" {
  name_prefix = "kyiv-instance-"
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.kyiv_lb.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "kyiv_lb" {
  name = "kyiv-lb"
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

  vpc_id = module.vpc.vpc_id
}

# Instance

resource "aws_instance" "kyiv" {
  ami           = "ami-830c94e3"
  instance_type = "t2.micro"

  tags = {
    Name = "ExampleAppServerInstance"
  }
}

# Launch config

resource "aws_launch_configuration" "kyiv" {
  name_prefix     = "kyiv-lc-"
  image_id        = aws_instance.kyiv.ami
  instance_type   = "t3.micro"
  user_data       = file("instance_setup.sh")
  security_groups = [aws_security_group.kyiv_lb.id]

  lifecycle {
    create_before_destroy = true # prevents interruptions, meaning that on update we will recreate resources and only then remove existing ones
  }
}

# Autoscaling

resource "aws_autoscaling_group" "kyiv" {
  min_size             = 1
  max_size             = 2
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.kyiv.name
  vpc_zone_identifier  = module.vpc.public_subnets
}

# Load Balancer

resource "aws_lb" "kyiv" {
  name               = "kyiv-lc"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.kyiv_lb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "kyiv" {
  load_balancer_arn = aws_lb.kyiv.arn # arn - Amazon Resource Name
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kyiv.arn
  }
}

resource "aws_lb_target_group" "kyiv" {
  name     = "kyiv"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

resource "aws_autoscaling_attachment" "kyiv" {
  autoscaling_group_name = aws_autoscaling_group.kyiv.id
  alb_target_group_arn   = aws_lb_target_group.kyiv.arn
}

