data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  azs = slice(
    data.aws_availability_zones.available.names,
    0,
    min(length(data.aws_availability_zones.available.names), length(var.public_subnet_cidrs))
  )

  versions = ["v1", "v2"]

  region_version_pairs = {
    for pair in setproduct(var.simulated_regions, local.versions) :
    "${pair[0]}-${pair[1]}" => {
      region  = pair[0]
      version = pair[1]
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = {
    for idx, cidr in var.public_subnet_cidrs : idx => cidr
  }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = local.azs[tonumber(each.key)]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB ingress"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "ECS tasks ingress from ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-sg"
  })
}

resource "aws_lb" "gateway" {
  name               = substr("${replace(local.name_prefix, "_", "-")}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "gateway" {
  for_each = local.region_version_pairs

  name        = substr("${replace(local.name_prefix, "_", "-")}-${each.value.region}-${each.value.version}", 0, 32)
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
  }

  tags = merge(local.tags, {
    Name          = "${local.name_prefix}-${each.value.region}-${each.value.version}-tg"
    LogicalRegion = each.value.region
    Version       = each.value.version
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.gateway.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({
        error = "missing X-Region header"
      })
      status_code = "400"
    }
  }
}

resource "aws_lb_listener_rule" "by_region" {
  for_each = {
    for idx, region in var.simulated_regions : region => idx
  }

  listener_arn = aws_lb_listener.http.arn
  priority     = 100 + each.value

  condition {
    http_header {
      http_header_name = "X-Region"
      values           = [each.key]
    }
  }

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.gateway["${each.key}-v1"].arn
        weight = 100 - lookup(var.v2_weights, each.key, 0)
      }

      target_group {
        arn    = aws_lb_target_group.gateway["${each.key}-v2"].arn
        weight = lookup(var.v2_weights, each.key, 0)
      }

      stickiness {
        enabled  = false
        duration = 60
      }
    }
  }
}

resource "aws_ecr_repository" "gateway" {
  for_each = toset(local.versions)

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Name    = "${var.project_name}-${each.key}"
    Version = each.key
  })
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_cloudwatch_log_group" "gateway" {
  for_each = local.region_version_pairs

  name              = "/ecs/${local.name_prefix}/${each.value.region}/${each.value.version}"
  retention_in_days = 14

  tags = local.tags
}

resource "aws_ecs_task_definition" "gateway" {
  for_each = local.region_version_pairs

  family                   = "${local.name_prefix}-${each.value.region}-${each.value.version}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "gateway"
      image     = var.gateway_images[each.value.version]
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PORT"
          value = "3000"
        },
        {
          name  = "REGION"
          value = each.value.region
        },
        {
          name  = "GATEWAY_VERSION"
          value = each.value.version
        },
        {
          name  = "CREDENTIALS_FILE"
          value = "/run/secrets/processor_credentials.env"
        }
      ]

      # Starter placeholder. In production, inject Secrets Manager/SSM values.
      secrets = [
        {
          name      = "PROCESSOR_API_KEY"
          valueFrom = "arn:aws:ssm:${var.aws_region}:111111111111:parameter/gateway/${each.value.region}/${each.value.version}/processor_api_key"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O- http://localhost:3000/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.gateway[each.key].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}

resource "aws_ecs_service" "gateway" {
  for_each = local.region_version_pairs

  name            = "${local.name_prefix}-${each.value.region}-${each.value.version}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.gateway[each.key].arn
  desired_count   = var.desired_count_per_service
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gateway[each.key].arn
    container_name   = "gateway"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(local.tags, {
    LogicalRegion = each.value.region
    Version       = each.value.version
  })

  depends_on = [
    aws_lb_listener_rule.by_region,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]
}
