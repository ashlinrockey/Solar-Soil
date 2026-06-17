import paho.mqtt.client as mqtt
import json
import time
import random

# MQTT Broker Configuration
BROKER = "broker.emqx.io"
PORT = 1883
TOPIC = "solarsoil/nodeA"

# Fixed for paho-mqtt 2.0+ compatibility
try:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
except AttributeError:
    client = mqtt.Client() # Fallback for older versions

def on_connect(client, userdata, flags, rc, properties=None):
    print(f"Connected with result code {rc}")

client.on_connect = on_connect
client.connect(BROKER, PORT, 60)

# Start background network loop to handle callbacks
client.loop_start()

print(f"Starting simulation on topic: {TOPIC} (Press Ctrl+C to stop)")

try:
    while True:
        data = {
            "temp": round(25 + random.uniform(0, 5), 1),
            "soil": random.randint(30, 60),
            "v": round(4.5 + random.uniform(0, 1.2), 1),
            "humidity": round(50 + random.uniform(0, 20), 1),
            "current": round(200 + random.uniform(0, 400), 1)
        }
        payload = json.dumps(data)
        print(f"Publishing: {payload}")
        client.publish(TOPIC, payload)
        time.sleep(5)
except KeyboardInterrupt:
    print("\nSimulation stopped.")
    client.loop_stop()
    client.disconnect()
