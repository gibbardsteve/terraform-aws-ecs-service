terraform {
  backend "s3" {
    bucket         = "sdp-dev-tf-state"
    key            = "sdp-dev-ecs-github-audit/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock"
  }

}

# Create Alias record to forward request to ALB
resource "aws_route53_record" "route53_record" {
  zone_id = data.aws_route53_zone.route53_domain.zone_id
  name    = "${local.service_url}"
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.ecs_infrastructure.outputs.service_lb_dns_name
    zone_id                = data.terraform_remote_state.ecs_infrastructure.outputs.service_lb_zone_id
    evaluate_target_health = true
  }

}

# Create target group, used by ALB to forward requests to ECS service
resource "aws_lb_target_group" "github_audit_fargate_tg" {
  name        = "${var.service_subdomain}-fargate-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.terraform_remote_state.ecs_infrastructure.outputs.vpc_id
}

# Create a listener rule to forward requests to the target group
resource "aws_lb_listener_rule" "github_audit_listener_rule" {
  listener_arn = data.terraform_remote_state.ecs_infrastructure.outputs.application_lb_https_listener_arn
  priority     = 10

  condition {
    host_header {
      values = ["${local.service_url}"]
    }
  }

  action {
    type = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.github_audit_user_pool.arn
      user_pool_client_id = aws_cognito_user_pool_client.userpool_client.id
      user_pool_domain    = aws_cognito_user_pool_domain.main.domain
    }
  }

  action {
    target_group_arn = aws_lb_target_group.github_audit_fargate_tg.arn
    type             = "forward"
  }
}

# Create a listener rule to forward requests to the target group
resource "aws_lb_listener_rule" "success_rule" {
  listener_arn = data.terraform_remote_state.ecs_infrastructure.outputs.application_lb_https_listener_arn
  priority     = 3

  condition {
    host_header {
      values = ["${local.service_url}"]
    }
  }

  condition {
    path_pattern {
      values = ["/success"]
    }
  }

  action {
    target_group_arn = aws_lb_target_group.github_audit_fargate_tg.arn
    type             = "forward"
  }
}

# Create a listener rule to forward requests to the target group
resource "aws_lb_listener_rule" "exempt_rule" {
  listener_arn = data.terraform_remote_state.ecs_infrastructure.outputs.application_lb_https_listener_arn
  priority     = 4

  condition {
    host_header {
      values = ["${local.service_url}"]
    }
  }

  condition {
    path_pattern {
      values = ["*set_exempt_date*"]
    }
  }

  action {
    target_group_arn = aws_lb_target_group.github_audit_fargate_tg.arn
    type             = "forward"
  }
}


# Security Group for the service
resource "aws_security_group" "allow_rules_service" {
  name        = "${var.service_subdomain}-allow-rule"
  description = "Allow inbound traffic on port ${var.container_port} from ${var.from_port} on the service"
  vpc_id      = data.terraform_remote_state.ecs_infrastructure.outputs.vpc_id

  ingress {
    from_port   = var.from_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Required for task execution to ensure logs are created in CloudWatch
resource "aws_cloudwatch_log_group" "ecs_service_logs" {
  name              = "/ecs/ecs-service-${var.service_subdomain}-application"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "ecs_service_definition" {
  family = "ecs-service-${var.service_subdomain}-application"
  container_definitions = jsonencode([
    {
      name      = "${var.service_subdomain}-task-application"
      image     = "${var.aws_account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.container_image}:${var.container_tag}"
      cpu       = 0,
      essential = true
      portMappings = [
        {
          name          = "${var.service_subdomain}-${var.container_port}-tcp",
          containerPort = var.container_port,
          hostPort      = var.container_port,
          protocol      = "tcp",
          appProtocol   = "http"
        }
      ],
      environment = [
        {
          name  = "AWS_ACCESS_KEY_ID"
          value = var.aws_access_key_id
        },
        {
          name  = "AWS_SECRET_ACCESS_KEY"
          value = var.aws_secret_access_key
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.region
        },
        {
          name  = "AWS_ACCOUNT_NAME"
          value = var.domain
        },
        {
          name  = "GITHUB_ORG"
          value = var.github_org
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-create-group"  = "true",
          "awslogs-group"         = "/ecs/ecs-service-${var.service_subdomain}-application",
          "awslogs-region"        = "${var.region}",
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
  execution_role_arn       = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.service_cpu
  memory                   = var.service_memory
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

}

resource "aws_ecs_service" "application" {
  name             = "${var.service_subdomain}-service"
  cluster          = data.terraform_remote_state.ecs_infrastructure.outputs.ecs_cluster_id
  task_definition  = aws_ecs_task_definition.ecs_service_definition.arn
  desired_count    = var.task_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  enable_ecs_managed_tags = true # It will tag the network interface with service name
  wait_for_steady_state   = true # Terraform will wait for the service to reach a steady state before continuing

  load_balancer {
    target_group_arn = aws_lb_target_group.github_audit_fargate_tg.arn
    container_name   = "${var.service_subdomain}-task-application"
    container_port   = var.container_port
  }

  # We need to wait until the target group is attached to the listener
  # and also the load balancer so we wait until the listener creation
  # is complete first
  network_configuration {
    subnets         = data.terraform_remote_state.ecs_infrastructure.outputs.private_subnets
    security_groups = [aws_security_group.allow_rules_service.id]

    # TODO: The container fails to launch unless a public IP is assigned
    # For a private ip, you would need to use a NAT Gateway?
    assign_public_ip = true
  }

}

# S3 Application Configuration
resource "aws_s3_bucket" "github_audit_bucket" {
  bucket = "${var.domain}-${var.service_subdomain}-tool"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.github_audit_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "blocked" {
  bucket = aws_s3_bucket.github_audit_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt_by_default" {
  bucket = aws_s3_bucket.github_audit_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "github_audit_user_pool" {
  name = "${var.domain}-${var.service_subdomain}-user-pool"

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 10
  }


  deletion_protection      = "INACTIVE"
  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_message_by_link = "Please click the link below to verify your email address with the ${var.service_subdomain} tool. {##Click Here##}"
  }

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_message = "You have been added as a user to the <a href='https://${local.service_url}/'>ONS Github Audit Tool</a><br>Your username is {username} and temporary password is <strong>{####}</strong>"
      email_subject = "Your access to the ${var.service_subdomain} tool"
      sms_message   = "Your username is {username} and temporary password is <strong>{####}</strong>"
    }
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true # false for "sub"
    required                 = true # true for "sub"
    string_attribute_constraints {  # if it is a string
      min_length = 0                # 10 for "birthdate"
      max_length = 2048             # 10 for "birthdate"
    }
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.service_subdomain}-${var.domain}"
  user_pool_id = aws_cognito_user_pool.github_audit_user_pool.id
}

resource "aws_cognito_user_pool_client" "userpool_client" {
  name                                 = "${var.service_subdomain}-client"
  user_pool_id                         = aws_cognito_user_pool.github_audit_user_pool.id
  callback_urls                        = ["https://${local.service_url}/oauth2/idpresponse"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret                      = true
  prevent_user_existence_errors        = "ENABLED"
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid"]
  supported_identity_providers         = ["COGNITO"]
}


