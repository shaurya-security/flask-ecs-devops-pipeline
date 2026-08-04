resource "aws_s3_bucket" "terraform_devops_state" {
  bucket = "shaurya-terraform-state-2000"

  tags = {
    Name    = "Terraform DevOps State"
    Project = "Terraform DevOps Bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "terraform_devops_state" {
  bucket = aws_s3_bucket.terraform_devops_state.id

  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_devops_state" {
  bucket = aws_s3_bucket.terraform_devops_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_devops_state" {
  bucket = aws_s3_bucket.terraform_devops_state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
