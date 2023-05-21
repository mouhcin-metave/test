terraform {
  backend "s3" {}
  # will be filled by Terragrunt
}

#######################################
######          LOCALS          #######
#######################################
# Les locals permettent la gestion des variables ainsi que les interpolations (modification sur une variable par exemple)
# Elles permettent ici de gérer des variables indispensables que sont l'environment, l'application, le service et la région
# Ces variables indispensables sont déduites du workspace, c'est ce qui permet de sélectionner l'environnement (et d'autres paramètres)
# Vous pouvez voir sur quel workspace vous vous situez en tappant la commande "terraform workspace list"


//-------------------    Declaration the local variables ------------


locals {

  block1={
    splitted_value        = split("-", terraform.workspace)
  application           = local.splitted_value[1]
  environment           = local.splitted_value[0]
  bucket_arn            = local.environment == "staging" ? "arn:aws:s3:::preprod-datalake-lakeformation-raw-data" : "arn:aws:s3:::${local.environment}-datalake-lakeformation-raw-data"
  event_rule_is_enabled = local.environment == "prod" ? false : true

  service = join(

    "-",
    [
      local.splitted_value[2],
      local.splitted_value[3],
    ],

  )
  region = join(
    "-",
    [
      local.splitted_value[4],
      local.splitted_value[5],
      local.splitted_value[6],
    ],
  )
  name_prefix = "${local.environment}-${local.application}-${local.service}"
  workspaces  = merge(local.dev, local.testing, local.staging, local.prod)
  workspace   = merge(local.workspaces[local.environment])
  tags = {
    "Service"     = local.service
    "Application" = local.application
    "Environment" = local.environment
  }
  }

  block2={
    name       = var.module
  account_id = data.aws_caller_identity.current.id
  tags = {
    Name        = "${var.environment}-${var.module}"
    Environment = var.environment
    Module      = var.module
    CreatedBy : "terraform"
  }


  }
  
  
}
###############################################
######          AWS RESSOURCES          #######
###############################################

//-------------------    Declaration the variables ------------

variable "aws_region" {
  description = "The AWS region to deploy on"
  type        = string
}

variable "environment" {
  type = string
}

variable "module" {
  type = string
}

variable "project" {
  type    = string
  default = "iad"
}

variable "artifacts_bucket_name" {
  type = string
}

variable "artifacts_bucket_arn" {
  type = string
}

variable "raw_bucket_arn" {
  type = string
}
variable "prepared_bucket_arn" {
  type = string
}

variable "prepared_bucket_name" {
  type = string
}

variable "people_db_name" {
  type = string
}

variable "common_ref_db_name" {
  type = string
}

variable "fct_comp_agnc_table_name" {
  type = string
}

variable "fct_comp_netw_table_name" {
  type = string
}

variable "fct_comp_flow_table_name" {
  type = string
}

variable "prepared_data_lf_location_arn" {
  type = string
}


variable "artifact_version" {
  type = string
}

variable "glue_common_version" {
  type = string
}

variable "project_root_path" {
  type = string
}

variable "people_subpackage" {
  type    = string
  default = "historical/people"
}

provider "aws" {
  region = var.aws_region
}
variable "database_name" {
  description = "The name of the AWS Glue catalog database"
  type        = string
  default     ="my_database"
}

// ---------   1.   aws_glue_catalog_table 

variable "fct_comp_mandats_table_name" {
  default = "fct_comp_mandats"
}

resource "aws_glue_catalog_table" "fct_comp_mandats" {
  depends_on    = [module.lf_permissions]
  name          = var.fct_comp_mandats_table_name
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    EXTERNAL              = "TRUE"
    "parquet.compression" = "SNAPPY"
  }

  storage_descriptor {
    location = lookup(
      local.current_table_locations,
      var.fct_comp_mandats_table_name,
      "s3://${var.prepared_bucket_name}/${aws_glue_catalog_database.this.name}/historical/${var.people_subpackage}/${var.fct_comp_mandats_table_name}/"
    )
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name    = "idnt_subs"
      type    = "string"
      comment = ""
    }
    columns {
      name    = "coun"
      type    = "string"
      comment = ""
    }
    columns {
      name    = "netw"
      type    = "string"
      comment = ""
    }
    columns {
      name    = "zip_code"
      type    = "string"
      comment = ""
    }
    columns {
      name    = "mand_count"
      type    = "int"
      comment = ""
    }
    columns {
      name    = "chck_date"
      type    = "string"
      comment = ""
    }
  }

  partition_keys {
    name = "idnt_month  "
    type = "string"
  }
}

//------------- 2.  aws_glue_job ----------------------
resource "aws_glue_job" "this" {
  name              = local.block2.name
  role_arn          = aws_iam_role.this.arn
  glue_version      = "2.0"
  number_of_workers = 2
  execution_property {
    max_concurrent_runs = 1
  }
  worker_type = "Standard"
  timeout     = 15
  default_arguments = {
    "--env"                              = var.environment
    "--region"                           = var.aws_region
    "--target_bucket"                    = var.prepared_bucket_name
    "--target_package"                   = var.people_subpackage
    "--target_db"                        = var.people_db_name
    "--target_table_agnc"                = var.fct_comp_agnc_table_name
    "--target_table_netw"                = var.fct_comp_netw_table_name
    "--target_table_flow"                = var.fct_comp_flow_table_name
    "--glue_endpoint"                    = "https://glue.${var.aws_region}.amazonaws.com"
    "--catalog_id"                       = local.block2.account_id
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--extra-py-files"                   = "s3://${var.artifacts_bucket_name}/glue-common/${var.glue_common_version}/glue_common.zip"
  }
  command {
    script_location = "s3://${var.artifacts_bucket_name}/fct-comp-agnt/fct-comp-agnt-${var.artifact_version}/fct_comp_agnt/main.py"
  }
  tags = merge(local.block2.tags, {
    Name = local.block2.name
  })
}

//------------------ 3.  aws_iam_role ----------------
resource "aws_iam_role" "this" {
  name = "${local.block2.name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    data.aws_iam_policy.AWSGlueServiceRole.arn
  ]
  tags = merge(local.block2.tags, {
    Name = "${local.block2.name}-role"
  })
  inline_policy {
    name = local.blocksname

    policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
          Sid : "AllowLFGetDataAccess"
          Effect : "Allow",
          Action : [
            "lakeformation:GetDataAccess"
          ],
          Resource : "*"
        },
        {
          Sid : "S3ReadOnly"
          Effect : "Allow",
          Action : [
            "s3:GetObject"
          ],
          Resource : [
            "${var.artifacts_bucket_arn}/*",
          "${var.raw_bucket_arn}/*"]
        },
        {
          Sid : "AllowS3DataAccess"
          Effect : "Allow",
          Action : [
            "s3:*"
          ],
          Resource : [
            "${var.prepared_bucket_arn}/*",
          var.prepared_bucket_arn]
        }
      ]
    })
  }
}  


//------------------ 4.  aws_cloudformation_stack ----------------

resource "aws_cloudformation_stack" "people_db_tables_permissions" {
  //  underscore is not authorized in stack name
  name = replace("${local.block2.name}-${var.people_db_name}", "_", "-")
  tags = merge(local.tags, {
    Name = replace("${local.block2.name}-${var.people_db_name}", "_", "-")
  })
  parameters = {
    DBName    = var.people_db_name
    Principal = aws_iam_role.this.arn
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/all_tables_reader_permissions.yaml")
  depends_on = [
  aws_iam_role.this]
}

resource "aws_cloudformation_stack" "common_ref_db_tables_permissions" {
  //  underscore is not authorized in stack name
  name = replace("${local.block2.name}-${var.common_ref_db_name}", "_", "-")
  tags = merge(local.block2.tags, {
    Name = replace("${local.block2.name}-${var.common_ref_db_name}", "_", "-")
  })
  parameters = {
    DBName    = var.common_ref_db_name
    Principal = aws_iam_role.this.arn
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/all_tables_reader_permissions.yaml")
  depends_on = [
  aws_iam_role.this]
}

resource "aws_cloudformation_stack" "fct_comp_agnc_table_permissions" {
  name = "${local.block2.name}-fct-comp-agnc-permissions"
  tags = merge(local.tags, {
    Name = "${local.block2.name}-fct-comp-agnc-permissions"
  })
  parameters = {
    DBName    = var.people_db_name
    Principal = aws_iam_role.this.arn
    TableName = var.fct_comp_agnc_table_name
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/table_admin_permissions.yaml")
  depends_on = [
  aws_iam_role.this]
}

resource "aws_cloudformation_stack" "fct_comp_netw_table_permissions" {
  name = "${local.block2.name}-fct-comp-netw-permissions"
  tags = merge(local.block2.tags, {
    Name = "${local.block2.name}-fct-comp-netw-permissions"
  })
  parameters = {
    DBName    = var.people_db_name
    Principal = aws_iam_role.this.arn
    TableName = var.fct_comp_netw_table_name
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/table_admin_permissions.yaml")
  depends_on = [
  aws_iam_role.this]
}

resource "aws_cloudformation_stack" "fct_comp_flow_table_permissions" {
  name = "${local.block2.name}-fct-comp-flow-permissions"
  tags = merge(local.tags, {
    Name = "${local.block2.name}-fct-comp-flow-permissions"
  })
  parameters = {
    DBName    = var.people_db_name
    Principal = aws_iam_role.this.arn
    TableName = var.fct_comp_flow_table_name
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/table_admin_permissions.yaml")
  depends_on = [
  aws_iam_role.this]
}

resource "aws_cloudformation_stack" "prepared_data_location_permissions" {
  name = "${local.block2.name}-prepared-data-location"
  tags = merge(local.block2.tags, {
    Name = "${local.block2.name}-prepared-data-location"
  })
  parameters = {
    Principal  = aws_iam_role.this.arn
    S3Resource = var.prepared_data_lf_location_arn
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/datalocation_access.yaml")
  depends_on = [
  aws_iam_role.this]
}


#spark.sql need access to default db to register tables
resource "aws_cloudformation_stack" "default_db_permissions" {
  name = "${local.block2.name}-default-db"
  tags = merge(local.block2.tags, {
    Name = "${local.block2.name}-default-db"
  })
  parameters = {
    Principal = aws_iam_role.this.arn
    DBName    = "default"
  }
  on_failure    = "ROLLBACK"
  template_body = file("${var.project_root_path}/common/cloudformation/lakeformation/db_admin_permissions.yaml")
  depends_on = [
  aws_iam_role.this]
}

// ---------- 5.     aws_lambda_function 
resource "aws_lambda_function" "my_lambda_function" {
  function_name    = "my-lambda-function"
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 128
  timeout          = 10
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("lambda_function.zip")
  
  # Add any additional Lambda function configuration as needed
}
// Lambda function to interact with the S3 bucket
resource "aws_lambda_permission" "s3_permission" {
  statement_id  = "AllowS3Invocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda_function.arn

  principal = "s3.amazonaws.com"
  
  source_arn = aws_s3_bucket.my_bucket.arn
}


// ---------- 6.     aws_s3_bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-bucket-name"
  acl    = "private"
  # Add more configuration options as needed
  output "bucket_arn" {
  value = aws_s3_bucket.my_bucket.arn
}

}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.my_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.my_lambda_function.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

// ------------ 7.  Athena ----------------------
data "aws_glue_catalog_table" "my_glue_table" {
  database_name = "my_database"
  table_name    = "my_table"
}

resource "aws_athena_named_query" "my_named_query" {
  database       = "my_database"
  name           = "my_named_query"
  query          = "CREATE TABLE my_athena_table AS SELECT * FROM ${data.aws_glue_catalog_table.fct_comp_mandats.arn}"
  result_configuration {
    output_location = "s3://my-bucket/path/"
  }
}

// 
resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "My Glue catalog database"
}

// ---------- 8.     State machine --------



resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "my-state-machine"
  role_arn = aws_iam_role.iam_for_sfn.arn

  definition = <<EOF
{
   "Comment": "Data Processing State Machine",
  "StartAt": "InvokeLambda",
  "States": {
    
   "InvokeLambda": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.my_lambda_function.arn}",
      "End": true
    },

 "StoreInS3": {
      "Type": "Task",
      "Resource": "arn:aws:states:::s3:PutObject",
      "Parameters": {
        "Bucket": "${aws_s3_bucket.my_bucket.id}",
      },
      "End": true
    },

    ......
    ........
    --------
    .......


  }


}
EOF
}




data "aws_iam_policy" "AWSGlueServiceRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
data "aws_caller_identity" "current" {}


output "job_role_arn" {
  value = aws_iam_role.this.arn
}
output "job_arn" {
  value = aws_glue_job.this.arn
}
output "job_name" {
  value = aws_glue_job.this.name
}