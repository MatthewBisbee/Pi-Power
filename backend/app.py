#File location on Pi: /home/chungy/powerbtn/app.py

from flask import Flask, abort, request
import subprocess

TOKEN = "bisbeepipower"
app = Flask(__name__)

@app.post("/press")
def press():
    if request.headers.get("X-Auth-Token") != TOKEN:
        abort(401)
    subprocess.run(["/home/chungy/poweron.sh"], check=True)
    return "OK\n"