import base64, os

os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Read index.html and encode
with open('index.html', 'rb') as f:
    index_data = f.read()
with open('index_b64.txt', 'w') as f:
    f.write(base64.b64encode(index_data).decode())

# Create empty data.json and encode
with open('data_b64.txt', 'w') as f:
    f.write(base64.b64encode(b'[]').decode())

print('OK - index.html size:', len(index_data), 'bytes')
print('b64 length:', len(base64.b64encode(index_data).decode()))
