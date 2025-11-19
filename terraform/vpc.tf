# --- Primary Region VPC ---
resource "aws_vpc" "primary" {
  provider   = aws.primary
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "primary-vpc"
  }
}

resource "aws_subnet" "primary_public_a" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.primary_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "primary-public-subnet-a"
  }
}

resource "aws_subnet" "primary_public_b" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary.id
  cidr_block        = "10.0.2.0/24" # Different CIDR block
  availability_zone = "${var.primary_region}b" # Different AZ
  map_public_ip_on_launch = true
  tags = {
    Name = "primary-public-subnet-b"
  }
}

# --- DR Region VPC ---
resource "aws_vpc" "dr" {
  provider   = aws.dr
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "dr-vpc"
  }
}

resource "aws_subnet" "dr_public_a" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "${var.dr_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "dr-public-subnet-a"
  }
}

resource "aws_subnet" "dr_public_b" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.2.0/24" # Different CIDR block
  availability_zone = "${var.dr_region}b" # Different AZ
  map_public_ip_on_launch = true
  tags = {
    Name = "dr-public-subnet-b"
  }
}

# --- Primary Region Networking ---
resource "aws_internet_gateway" "primary_gw" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary.id
  tags = {
    Name = "primary-igw"
  }
}

resource "aws_route_table" "primary_rt" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_gw.id
  }

  tags = {
    Name = "primary-public-rt"
  }
}

resource "aws_route_table_association" "primary_a" {
  provider       = aws.primary
  subnet_id      = aws_subnet.primary_public_a.id
  route_table_id = aws_route_table.primary_rt.id
}

resource "aws_route_table_association" "primary_b" {
  provider       = aws.primary
  subnet_id      = aws_subnet.primary_public_b.id
  route_table_id = aws_route_table.primary_rt.id
}


# --- DR Region Networking ---
resource "aws_internet_gateway" "dr_gw" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id
  tags = {
    Name = "dr-igw"
  }
}

resource "aws_route_table" "dr_rt" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr_gw.id
  }

  tags = {
    Name = "dr-public-rt"
  }
}

resource "aws_route_table_association" "dr_a" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_public_a.id
  route_table_id = aws_route_table.dr_rt.id
}

resource "aws_route_table_association" "dr_b" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_public_b.id
  route_table_id = aws_route_table.dr_rt.id
}