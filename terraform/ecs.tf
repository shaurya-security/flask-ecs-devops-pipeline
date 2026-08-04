resource "aws_ecs_cluster" "main" {
  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "flask" {

  family                   = local.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = local.task_cpu
  memory = local.task_memory

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name = local.project_name

      image = "${aws_ecr_repository.app.repository_url}:3.0"

      essential = true

      portMappings = [
        {
          containerPort = local.container_port
          hostPort      = 5000
        }
      ]

      environment = [
        {
          name  = "APP_NAME"
          value = local.project_name
        },
        {
          name  = "APP_VERSION"
          value = "3.0"
        },
        {
          name  = "DEBUG"
          value = "False"
        }
      ]


      logConfiguration = {

        logDriver = "awslogs"

        options = {

          awslogs-group = aws_cloudwatch_log_group.ecs.name

          awslogs-region = local.aws_region

          awslogs-stream-prefix = "ecs"

        }
      }
    }
  ])
}



resource "aws_ecs_service" "flask" {

  name    = local.ecs_service_name
  cluster = aws_ecs_cluster.main.id

  task_definition = aws_ecs_task_definition.flask.arn

  desired_count = 1

  launch_type = "FARGATE"

  network_configuration {

    subnets = aws_subnet.private[*].id

    security_groups = [
      aws_security_group.ecs_task_sg.id
    ]

    assign_public_ip = false
  }

  load_balancer {

    target_group_arn = aws_lb_target_group.flask.arn

    container_name = local.project_name

    container_port = local.container_port
  }

  depends_on = [
    aws_lb_listener.http
  ]
}
