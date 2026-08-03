import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    APP_NAME = os.getenv("APP_NAME", "Flask Demo")
    APP_VERSION = os.getenv("APP_VERSION", "0.0.1")
    DEBUG = os.getenv("DEBUG", "False").lower() == "true"
