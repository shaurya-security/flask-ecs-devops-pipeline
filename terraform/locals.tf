locals {
  owner        = var.owner
  vpc_name     = "${local.owner}-vpc"
  igw_name     = "${local.owner}-igw"
  project_name = "flask-ecs-cicd-demo"

  # Subnet naming architecture
  subnet_name         = "${local.owner}-subnet"
  public_subnet_name  = "${local.subnet_name}-public"
  private_subnet_name = "${local.subnet_name}-private"

  # Route table naming architecture
  rtb_name         = "${local.owner}-rtb"
  public_rtb_name  = "${local.rtb_name}-public"
  private_rtb_name = "${local.rtb_name}-private"

  # Security Group naming architecture (Replaced EC2/Bastion with ALB/ECS)
  sg_name     = "${local.owner}-sg"
  alb_sg_name = "${local.sg_name}-alb"
  ecs_sg_name = "${local.sg_name}-ecs-task"

  # ECS & Cluster naming infrastructure
  ecs_cluster_name = "${local.owner}-ecs-cluster"
  ecs_service_name = "${local.owner}-flask-service"
  alb_name         = "${local.owner}-alb"


  # Resource Tag Tracking System
  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
    Owner     = local.owner
  }

  # ECS Compute Config
  container_port = 5000
  aws_region     = "ap-south-1"
  task_cpu       = 256
  task_memory    = 512

}
