resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.vpc_name
  }
}

# Dynamically create Public Subnets across multiple AZs
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.public_subnet_name}-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Dynamically create Private Subnets across multiple AZs
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.private_subnet_name}-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.igw_name
  }
}

resource "aws_route_table" "public_rtb" {
  count = length(var.public_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.public_rtb_name}-${data.aws_availability_zones.available.names[count.index]}"

  }
}

resource "aws_route_table" "private_rtb" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.private_rtb_name}-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_route_table_association" "public_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rtb[count.index].id
}

resource "aws_route_table_association" "private_association" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rtb[count.index].id
}


# 1. ALB Security Group: Accepts public HTTP traffic from the internet
resource "aws_security_group" "alb_sg" {
  name        = "${local.vpc_name}-alb-sg"
  description = "Allows public web traffic to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic to ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.vpc_name}-alb-sg"
  }
}

# 2. ECS Task Security Group: Strictly accepts traffic ONLY from the ALB
resource "aws_security_group" "ecs_task_sg" {
  name        = "${local.vpc_name}-ecs-task-sg"
  description = "Allows traffic only from the ALB to Flask app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow traffic on Flask port from ALB only"
    from_port       = 5000 # Change this if your Flask app runs on a different port (e.g., 8080)
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Locks down access strictly to your ALB
  }

  egress {
    description = "Allow all outbound traffic via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Needed to pull ECR images and hit public APIs
  }

  tags = {
    Name = "${local.vpc_name}-ecs-task-sg"
  }
}



resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nat-eip" }
}

resource "aws_nat_gateway" "main" {

  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "main-nat-gateway" }
}

resource "aws_route" "private_nat" {
  count                  = length(var.private_subnet_cidrs)
  route_table_id         = aws_route_table.private_rtb[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = aws_nat_gateway.main.id
}
