import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    APP_NAME = os.getenv("APP_NAME", "flask-ecs-devops-pipeline")
    APP_VERSION = os.getenv("APP_VERSION", "dev-local")
    DEBUG = os.getenv("DEBUG", "False").lower() == "true"
    CUSTOM_MESSAGE = os.getenv("CUSTOM_MESSAGE", "Welcome to the ECS CI/CD Deployment!")
