# Definição do provider AWS
provider "aws" {
  region = "us-east-1" # Defina a região desejada
}

# Criação de uma VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Criação de uma sub-rede pública
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

# Criação de uma sub-rede pública adicional em outra zona de disponibilidade
resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Gateway da Internet para permitir acesso à Internet na VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Associação do gateway da Internet à VPC
resource "aws_route" "internet_gateway" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Criação de um security group para permitir tráfego entre os serviços
resource "aws_security_group" "metabase_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Criação de um serviço ECS (Elastic Container Service)
resource "aws_ecs_cluster" "metabase_cluster" {
  name = "metabase-cluster"
}

# Criação de uma tarefa ECS para o Metabase
resource "aws_ecs_task_definition" "metabase_task" {
  family                   = "metabase-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      "name": "metabase",
      "image": "metabase/metabase:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000,
          "protocol": "tcp"
        }
      ],
      "cpu": 256,
      "memory": 512
    }
  ])
}

# Criação de um serviço ECS para executar a tarefa do Metabase
resource "aws_ecs_service" "metabase_service" {
  name            = "metabase-service"
  cluster         = aws_ecs_cluster.metabase_cluster.id
  task_definition = aws_ecs_task_definition.metabase_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.subnet2.id] # Sub-rede pública adicional
    security_groups = [aws_security_group.metabase_sg.id]
  }
}

# Criação de uma instância de banco de dados MySQL
resource "aws_db_instance" "metabase_db" {
  identifier               = "metabase-db"
  allocated_storage        = 20
  engine                   = "mysql"
  engine_version           = "5.7"
  instance_class           = "db.t2.micro"
  username                 = "admin"
  password                 = "maistodos"
  parameter_group_name     = "default.mysql5.7"
  publicly_accessible      = true
  # Defina um identificador para o snapshot final do banco de dados
  final_snapshot_identifier= "snapshot"
  skip_final_snapshot      = true
}


# Grupo de sub-redes para a instância do banco de dados MySQL
resource "aws_db_subnet_group" "metabase_db_subnet_group" {
  name       = "metabase-db-subnet-group"
  subnet_ids = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}