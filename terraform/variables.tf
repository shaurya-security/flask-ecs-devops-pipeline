variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "owner" {
  type    = string
  default = "shaurya-devops"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
  description = "CIDR blocks for private subnets"
}

variable "github_owner" {
  description = "GitHub organization or username"
  type        = string
  default     = "shaurya-security"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "flask-ecs-cicd-demo"
}
