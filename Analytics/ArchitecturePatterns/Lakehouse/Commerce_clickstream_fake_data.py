
from confluent_kafka import Producer,Consumer
import sys
import json
import datetime
import uuid
import random
import time
from datetime import timedelta

conf = {
    'bootstrap.servers': 'salabcommerce-eventhubs.servicebus.windows.net:9093',
    'security.protocol': 'SASL_SSL',
    'sasl.mechanism': 'PLAIN',
    'sasl.username': '$ConnectionString',
    'ssl.ca.location': 'C:\CodeDevelopment\Python\cacert1.pem',  
    'sasl.password': 'Endpoint=sb://salabcommerce-eventhubs.servicebus.windows.net/;SharedAccessKeyName=EH-ASA-Access;SharedAccessKey=xxxxxxxxxxxxxxxx',
    'client.id': 'python-example-producer'
}

# Create Producer instance
p = Producer(**conf)


def delivery_callback(err, msg):
    if err:
        sys.stderr.write('%% Message failed delivery: %s\n' % err)
    else:
        print('Message delivered to {} {} @{} {} \n'.format(msg.topic(), msg.partition(), msg.offset(),msg.value()))


#  topic name which is the event hub name
topic= 'clickstream-eventhub'

# clickstream data is generated for on below 5 customers
customers = ['US_SI_0062', 'US_SI_0063', 'US_SI_0064', 'US_SI_0065', 'US_SI_0066']

items = ['D0001', 'D0002', 'D0003', 'L0001', 'M0001', 'M0002' ]

devices = ['mobile', 'computer', 'tablet']

events = 	[
            "Search",
            "AddToCart",
            "DeleteFromCart",
            "IncreaseQuantity",
            "DecreaseQuantity",
            "AddPromoCode",
            "Checkout",
            "Login",
            "Logout",
            "CheckoutAsGuest"
            "CompleteOrder",
            "CheckOrderStatus" ]

def get_session_id():
    MAX_USER_ID = 999999
    MIN_USER_ID = 100000

    return random.randint(MIN_USER_ID, MAX_USER_ID)


for cust in customers:    

    for y in range(0,random.randrange(20)): # For each customer, produce upto 20 events max.   
        try:
        # Create a dummy reading.
            print(y)

            reading = {          
            'itemid': random.choice(items),  
            'userid': cust, 
            'device' : random.choice(devices),
            'sessionid': get_session_id(),
            'event_name' : random.choice(events),           
            'date': str(datetime.datetime.utcnow()+timedelta(hours=y))
            }

            msgformatted = json.dumps(reading) # Convert the reading into a JSON object.
            p.produce(topic, msgformatted, callback=delivery_callback)
            p.flush()
            # time.sleep(1)

        except BufferError as e:
            sys.stderr.write('some error')

sys.stderr.write('%% Waiting for %d deliveries\n' % len(p))
p.flush()

