provider "aws" {
  region = "ap-southeast-2" 
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "main_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-2a"

  map_public_ip_on_launch = true  # Assign public IPs to instances in this subnet

  tags = {
    Name = "main-subnet"
  }
}

resource "aws_security_group" "app_security_group" {
  name        = "MyWebAppSG"
  description = "Allow SSH, Streamlit, and PostgreSQL traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]  # Replace with your actual IP address for SSH access
    description = "Allow SSH access"
  }

  ingress {
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]   # Allow access from anywhere
    description = "Allow Streamlit access"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]   # Allow access from anywhere
    description = "Allow PostgreSQL access"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
    description = "Allow HTTP access"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
    description = "Allow HTTPS access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks  = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_instance" {
  ami           = "ami-0474411b350de35fb" 
  instance_type = "g4dn.xlarge" 
  key_name      = "llama-setup" 

  vpc_security_group_ids = [aws_security_group.app_security_group.id]
  subnet_id = aws_subnet.main_subnet.id  

  root_block_device {
    volume_size = 100  # Set the root volume size to 100 GB
    volume_type = "gp3"  # General-purpose SSD
  }

  user_data = <<-EOF
              #!/bin/bash
              export HOME=/home/ec2-user 
              set -x  # Enable debugging
              exec > >(tee /var/log/user-data.log) 2>&1  

              # Update and install necessary packages
              yum update -y
              yum install -y docker git python3 python3-pip

              # Start Docker service
              systemctl enable docker
              systemctl start docker

              # Add ec2-user to the docker group
              usermod -aG docker ec2-user

              # Install Ollama
              curl -fsSL https://ollama.com/install.sh | sh || { echo 'Ollama installation failed'; exit 1; }

              #start Ollama
              nohup ollama serve > ollama.log 2>&1 &

              # Verify installation
              ollama --version || { echo 'Ollama version check failed'; exit 1; }

              # Install Docker Compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo 'Docker Compose installation failed'; exit 1; }
              chmod +x /usr/local/bin/docker-compose

              # Clone your repository
              git clone https://github.com/NAVEENKUMARMURUGAN/llama-test-data-genenrator.git /home/ec2-user/app || { echo 'Git clone failed'; exit 1; }
              cd /home/ec2-user/app

              # Create the Docker container for PostgreSQL
              docker-compose up -d || { echo 'Docker Compose up failed'; exit 1; }

              # Run Ollama to create the model
              ollama create "llama-synta" -f ./synta || { echo 'Ollama create failed'; exit 1; }

              # Install required Python packages
              pip3 install --user -r requirements.txt || { echo 'Python packages installation failed'; exit 1; }
              
              # Run the Streamlit application
              nohup streamlit run app.py --server.port 8501 &
              EOF

  tags = {
    Name = "MyWebAppInstance"
  }
}
