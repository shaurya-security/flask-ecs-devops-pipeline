from flask import Flask, jsonify, render_template
from config import Config

app = Flask(__name__)


@app.route("/")
def home():
    return render_template(
        "index.html",
        app_name=Config.APP_NAME,
        version=Config.APP_VERSION,
        message=Config.CUSTOM_MESSAGE,
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

@app.route("/info")
def info():
    return jsonify({
        "application": Config.APP_NAME,
        "version": Config.APP_VERSION,
        "server": "gunicorn"
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=Config.DEBUG)
