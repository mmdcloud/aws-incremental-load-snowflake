# Registering vault provider
data "vault_generic_secret" "redshift" {
  path = "secret/redshift"
}

resource "random_id" "id" {
  byte_length = 8
}

# -----------------------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------------------

module "vpc" {
  source                = "./modules/vpc/vpc"
  vpc_name              = "vpc"
  vpc_cidr_block        = "10.0.0.0/16"
  enable_dns_hostnames  = true
  enable_dns_support    = true
  internet_gateway_name = "vpc_igw"
}

# Security Group
module "redshift_security_group" {
  source = "./modules/vpc/security_groups"
  vpc_id = module.vpc.vpc_id
  name   = "redshift-security-group"
  ingress = [
    {
      from_port       = 5439
      to_port         = 5439
      protocol        = "tcp"
      self            = "false"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
      description     = "any"
    },
    {
      from_port       = 0
      to_port         = 0
      protocol        = "tcp"
      self            = "true"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
      description     = "any"
    }
  ]
  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# Public Subnets
module "public_subnets" {
  source = "./modules/vpc/subnets"
  name   = "public-subnet"
  subnets = [
    {
      subnet = "10.0.1.0/24"
      az     = "${var.region}a"
    },
    {
      subnet = "10.0.2.0/24"
      az     = "${var.region}b"
    },
    {
      subnet = "10.0.3.0/24"
      az     = "${var.region}c"
    },
    {
      subnet = "10.0.4.0/24"
      az     = "${var.region}d"
    },
    {
      subnet = "10.0.5.0/24"
      az     = "${var.region}e"
    },
    {
      subnet = "10.0.6.0/24"
      az     = "${var.region}f"
    }
  ]
  vpc_id                  = module.vpc.vpc_id
  map_public_ip_on_launch = true
}

# Private Subnets
module "private_subnets" {
  source = "./modules/vpc/subnets"
  name   = "private-subnet"
  subnets = [
    {
      subnet = "10.0.7.0/24"
      az     = "${var.region}a"
    },
    {
      subnet = "10.0.8.0/24"
      az     = "${var.region}b"
    },
    {
      subnet = "10.0.9.0/24"
      az     = "${var.region}c"
    }
  ]
  vpc_id                  = module.vpc.vpc_id
  map_public_ip_on_launch = false
}

# Public Route Table
module "public_rt" {
  source  = "./modules/vpc/route_tables"
  name    = "public-route-table"
  subnets = module.public_subnets.subnets[*]
  routes = [
    {
      cidr_block         = "0.0.0.0/0"
      gateway_id         = module.vpc.igw_id
      nat_gateway_id     = ""
      transit_gateway_id = ""
    }
  ]
  vpc_id = module.vpc.vpc_id
}

# Private Route Table
module "private_rt" {
  source  = "./modules/vpc/route_tables"
  name    = "private-route-table"
  subnets = module.private_subnets.subnets[*]
  routes  = []
  vpc_id  = module.vpc.vpc_id
}

# -----------------------------------------------------------------------------------------
# VPC Endpoint Configuration
# -----------------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.private_rt.id]

  tags = {
    Name = "s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "kms_endpoint" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.region}.kms"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.public_subnets.subnets[*].id
  security_group_ids = [module.redshift_security_group.id]

  tags = {
    Name = "kms-endpoint"
  }
}

resource "aws_vpc_endpoint" "sts_endpoint" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.public_subnets.subnets[*].id
  security_group_ids = [module.redshift_security_group.id]

  tags = {
    Name = "sts-endpoint"
  }
}

resource "aws_vpc_endpoint" "redshift_endpoint" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.region}.redshift"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.public_subnets.subnets[*].id
  security_group_ids = [module.redshift_security_group.id]

  tags = {
    Name = "redshift-endpoint"
  }
}

resource "aws_vpc_endpoint" "secrets_manager_endpoint" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.public_subnets.subnets[*].id
  security_group_ids = [module.redshift_security_group.id]

  tags = {
    Name = "secrets-manager-endpoint"
  }
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "source_bucket" {
  source             = "./modules/s3"
  bucket_name        = "source-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "glue_etl_script_bucket" {
  source      = "./modules/s3"
  bucket_name = "glue-etl-script-bucket-${random_id.id.hex}"
  objects = [
    {
      key    = "etl_job.py"
      source = "../src/etl_job.py"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

# -----------------------------------------------------------------------------------------
# Redshift Configuration
# -----------------------------------------------------------------------------------------
module "redshift_serverless" {
  source              = "./modules/redshift"
  namespace_name      = "incremental-load-namespace"
  admin_username      = data.vault_generic_secret.redshift.data["username"]
  admin_user_password = data.vault_generic_secret.redshift.data["password"]
  db_name             = "incremental-load-db"
  workgroups = [
    {
      workgroup_name      = "incremental-load-workgroup"
      base_capacity       = 128
      publicly_accessible = false
      subnet_ids          = module.public_subnets.subnets[*].id
      security_group_ids  = [module.redshift_security_group.id]
      config_parameters = [
        {
          parameter_key   = "enable_user_activity_logging"
          parameter_value = "true"
        }
      ]
    }
  ]
}

# -----------------------------------------------------------------------------------------
# Glue Configuration
# -----------------------------------------------------------------------------------------
resource "aws_iam_role" "glue_crawler_role" {
  name = "glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_policy" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "s3_access_policy" {
  role = aws_iam_role.glue_crawler_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "${module.source_bucket.arn}",
          "${module.source_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_glue_catalog_database" "database" {
  name        = var.glue_database_name
  description = "Glue database for incremental load"
}

resource "aws_glue_catalog_table" "table" {
  name          = var.glue_table_name
  database_name = aws_glue_catalog_database.database.name
}

resource "aws_glue_crawler" "crawler" {
  database_name = aws_glue_catalog_database.database.name
  name          = var.glue_crawler_name
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${module.source_bucket.bucket}"
  }
}

resource "aws_glue_connection" "redshift_conn" {
  name            = "redshift-connection"
  description     = "Glue connection to Amazon Redshift"
  connection_type = "JDBC"

  # Connection properties for Redshift
  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:redshift://${tostring(module.redshift_serverless.endpoint)}:5439/incremental-load-db"
    USERNAME            = "${data.vault_generic_secret.redshift.data["username"]}"
    PASSWORD            = "${data.vault_generic_secret.redshift.data["password"]}"
    # Optionally, use AWS Secrets Manager for credentials
    # SECRET_ID         = "<aws_secretsmanager_secret_arn>"
  }
  physical_connection_requirements {
    subnet_id              = module.public_subnets.subnets[0].id
    security_group_id_list = [module.redshift_security_group.id]
    availability_zone      = module.public_subnets.subnets[0].availability_zone
  }
}


# IAM role for Glue jobs
resource "aws_iam_role" "glue_job_role" {
  name = "glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_job_role_policy_redshift" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRedshiftFullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_job_role_policy_s3" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_job_role_policy_console" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_job_role_policy_iam" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_job_role_policy_kms" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
}

resource "aws_iam_role_policy_attachment" "secrets_manager_read_write" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_glue_job" "etl_job" {
  name              = "etl-job"
  description       = "Incremental load ETL job"
  role_arn          = aws_iam_role.glue_job_role.arn
  glue_version      = "5.0"
  max_retries       = 0
  timeout           = 2880
  number_of_workers = 2
  worker_type       = "G.1X"
  connections       = [aws_glue_connection.redshift_conn.name]
  execution_class   = "STANDARD"

  command {
    script_location = "s3://${module.glue_etl_script_bucket.bucket}/etl_job.py"
    name            = "glueetl"
    python_version  = "3"
  }

  notification_property {
    notify_delay_after = 3 # delay in minutes
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--enable-auto-scaling"              = "true"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    "ManagedBy" = "AWS"
  }
}