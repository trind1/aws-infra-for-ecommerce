locals {
  name = "${var.project_name}-${var.environment}"

  public_subnets = {
    for index, cidr in var.public_subnet_cidrs : tostring(index + 1) => {
      cidr_block        = cidr
      availability_zone = var.availability_zones[index]
    }
  }

  database_subnets = {
    for index, cidr in var.database_subnet_cidrs : tostring(index + 1) => {
      cidr_block        = cidr
      availability_zone = var.availability_zones[index]
    }
  }
}


# ============ VPC  ============
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = local.name
    Component = "network"
  }
}

# ============ INTERNET GATEWAY  ============
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${local.name}-igw"
    Component = "network"
  }
}

# ============ PUBLIC SUBNETS  ============
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${each.key}"
    Tier = "public"
  }
}

# ============ PUBLIC ROUTE TABLE  ============
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name      = "${local.name}-public-rt"
    Component = "network"
    Tier      = "public"
  }
}

# ============ PUBLIC ROUTE TABLE ASSOCIATIONS  ============
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ============ PRIVATE DATABASE SUBNETS  ============
resource "aws_subnet" "database" {
  for_each = local.database_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = "${local.name}-db-${each.key}"
    Tier = "database"
  }
}

# ============ DATABASE ROUTE TABLE  ============
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id

  # No default route is intentional: the database tier has no direct internet path.
  tags = {
    Name      = "${local.name}-db-rt"
    Component = "network"
    Tier      = "database"
  }
}

# ============ DATABASE ROUTE TABLE ASSOCIATIONS  ============
resource "aws_route_table_association" "database" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}
