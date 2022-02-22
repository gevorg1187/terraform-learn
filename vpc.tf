provider "aws" {
  region = "eu-central-1"
}
# vpc
resource "aws_vpc" "vpc-test" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }

}

# public subnet 1
resource "aws_subnet" "public_subnet_1" {
  depends_on = [
    aws_vpc.vpc-test,
  ]

  vpc_id     = aws_vpc.vpc-test.id
  cidr_block = "192.168.0.0/24"

  availability_zone_id = "euc1-az2"

  tags = {
    Name = "public-subnet_1"
  }

  map_public_ip_on_launch = true
}


# public subnet 2
resource "aws_subnet" "public_subnet_2" {
  depends_on = [
    aws_vpc.vpc-test,
  ]

  vpc_id     = aws_vpc.vpc-test.id
  cidr_block = "192.168.1.0/24"

  availability_zone_id = "euc1-az3"

  tags = {
    Name = "public-subnet_2"
  }

  map_public_ip_on_launch = true
}

# private subnet 1
resource "aws_subnet" "private_subnet_1" {
  depends_on = [
    aws_vpc.vpc-test,
  ]

  vpc_id     = aws_vpc.vpc-test.id
  cidr_block = "192.168.2.0/24"

  availability_zone_id = "euc1-az2"

  tags = {
    Name = "private-subnet_1"
  }
}

# private subnet 1
resource "aws_subnet" "private_subnet_2" {
  depends_on = [
    aws_vpc.vpc-test,
  ]

  vpc_id     = aws_vpc.vpc-test.id
  cidr_block = "192.168.3.0/24"


  availability_zone_id = "euc1-az3"

  tags = {
    Name = "private-subnet_2"
  }
}


# internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  depends_on = [
    aws_vpc.vpc-test,
  ]

  vpc_id = aws_vpc.vpc-test.id

  tags = {
    Name = "internet-gateway"
  }
}


# route table with target as internet gateway
resource "aws_route_table" "IG_route_table" {
  depends_on = [
    aws_vpc.vpc-test,
    aws_internet_gateway.internet_gateway,
  ]

  vpc_id = aws_vpc.vpc-test.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "IG-route-table"
  }
}

# associate route table to public subnet 1
resource "aws_route_table_association" "associate_routetable_to_public_subnet_1" {
  depends_on = [
    aws_subnet.public_subnet_1,
    aws_route_table.IG_route_table,
  ]
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.IG_route_table.id
}


# associate route table to public subnet 2
resource "aws_route_table_association" "associate_routetable_to_public_subnet_2" {
  depends_on = [
    aws_subnet.public_subnet_2,
    aws_route_table.IG_route_table,
  ]
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.IG_route_table.id
}


# elastic ip
resource "aws_eip" "elastic_ip" {
  vpc = true
}

# NAT gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on = [
    aws_subnet.public_subnet_1,
    aws_eip.elastic_ip,
  ]
  allocation_id = aws_eip.elastic_ip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "nat-gateway"
  }
}

# route table with target as NAT gateway
resource "aws_route_table" "NAT_route_table" {
  depends_on = [
    aws_vpc.vpc-test,
    aws_nat_gateway.nat_gateway,
  ]

  vpc_id = aws_vpc.vpc-test.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "NAT-route-table"
  }
}

# associate route table to private subnet_1
resource "aws_route_table_association" "associate_routetable_to_private_subnet_1" {
  depends_on = [
    aws_subnet.private_subnet_1,
    aws_route_table.NAT_route_table,
  ]
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.NAT_route_table.id
}

# associate route table to private subnet_2
resource "aws_route_table_association" "associate_routetable_to_private_subnet_2" {
  depends_on = [
    aws_subnet.private_subnet_2,
    aws_route_table.NAT_route_table,
  ]
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.NAT_route_table.id
}


# dynamic web security_group


resource "aws_security_group" "web-sg" {
  name   = "Dynamic Security Group"
  vpc_id = aws_vpc.vpc-test.id


  dynamic "ingress" {
    for_each = ["80", "443"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {

    Name  = "Dynamic Security Group"
    Owner = "Gevorg Arabyan"
  }
}

#AMI
data "aws_ami" "latest_amazon_linux" {
  owners   = ["amazon"]
  most_recent = true
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
# aws launch configuration


resource "aws_launch_configuration" "web" {
  name_prefix     = "WebServer-Highly-Available-"
  image_id        = data.aws_ami.latest_amazon_linux.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web-sg.id]
  user_data       = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}


data "aws_availability_zones" "available" {
  state = "available"
}


# ALB security group
resource "aws_security_group" "lb-sg" {
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.vpc-test.id

  ingress {
    description = "allow TCP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow TCP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//Auto-Scaling Group

resource "aws_autoscaling_group" "web" {
  name                 = "ASG-${aws_launch_configuration.web.name}"
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 2
  max_size             = 3
  min_elb_capacity     = 2
  #vpc_id               = aws_vpc.vpc-test.id
  vpc_zone_identifier = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.alb-target.arn]

  dynamic "tag" {
    for_each = {
      Name   = "WebServer in ASG"
      Owner  = "Gevorg Arabyan"
      TAGKEY = "TAGVALUE"
    }
    content {

      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  lifecycle {
    create_before_destroy = true
  }

}

//autosaling group attach to ALB
resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.web.id
  alb_target_group_arn    = aws_lb_target_group.alb-target.arn
}


//Create target group
resource "aws_lb_target_group" "alb-target" {
  name     = "alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-test.id
}


// ALB
resource "aws_lb" "alb-web" {
  name               = "alb-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb-sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
   tags = {
    Environment = "production"
  }
}

//Add listener
resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.alb-web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target.arn
  }
}



output "web_loadbalancer_url" {
  value = aws_lb.alb-web.dns_name
}
