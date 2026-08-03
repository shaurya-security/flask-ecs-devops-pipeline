from flask import Flask, jsonify, render_template
from config import Config

app = Flask(__name__)


@app.route("/")
def home():
    return render_template(
        "index.html",
        app_name=Config.APP_NAME,
        version=Config.APP_VERSION,
    )


@app.route("/health")
def health():
    return jsonify(
        {
            "status": "healthy",
            "application": Config.APP_NAME,
            "version": Config.APP_VERSION,
        }
    )


if __name__ == "__main__":
    app.run(debug=Config.DEBUG)
