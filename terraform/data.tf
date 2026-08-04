# Dynamically fetch all available AZs in your current provider region (e.g., ap-south-1)
data "aws_availability_zones" "available" {
  state = "available"
}

