data "aws_availability_zones" "available" {}

#Create the vpc for the cluster
resource "aws_vpc" "main" {
  cidr_block            = var.vpc_cidr_block
  enable_dns_hostnames  = true
  enable_dns_support = true
  tags = {
    Name                = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}"      = "owned"
  }
}

#create the private subnets
resource "aws_subnet" "private" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]

  tags = {
    Name = "private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}"      = "owned"
    "karpenter.sh/discovery" = var.cluster_name
  }
}

#create public subnets
resource "aws_subnet" "public" {
  count             = var.public_subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index + var.private_subnet_count)
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]

  tags = {
    Name = "public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb"                    = "1"  
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

#create internet gateway for public subnets
resource "aws_internet_gateway" "main" {
  vpc_id                = aws_vpc.main.id

  tags = {
    Name                = "${var.cluster_name}-igw"
  }
}

#create elatic ip to be attached to nat gateway
resource "aws_eip" "main" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

#create nat gatway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.main.id
  subnet_id = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

#create public route table
resource "aws_route_table" "public" {
  vpc_id                = aws_vpc.main.id

  route {
    cidr_block          = "0.0.0.0/0"
    gateway_id          = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.cluster_name}-public"
  }
}

#create private route table
resource "aws_route_table" "private" {
  vpc_id                = aws_vpc.main.id

  route {
    cidr_block          = "0.0.0.0/0"
    nat_gateway_id      = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.cluster_name}-private"
  }
}

#create route table association for public route table
resource "aws_route_table_association" "public" {
  count = var.public_subnet_count
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#create route table association for private route table
resource "aws_route_table_association" "private" {
  count = var.private_subnet_count
  subnet_id = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

#Create ec2 instance connect endpoint to access the instances in the private subnet_id
resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = aws_subnet.private[1 % var.private_subnet_count].id
  security_group_ids = [var.eice_sg_id]
  preserve_client_ip = false

  tags = {
    Name = "K8s-Cluster-Connect-Endpoint"
  }
}