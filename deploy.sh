#!/bin/bash

# Variables
PROJECT_NAME="test-deploy"
GITHUB_REPO_URL="https://github.com/gajjug004/test-deploy.git"
PROJECT_DIR="/home/ubuntu/$PROJECT_NAME"
VENV_DIR="$PROJECT_DIR/venv"
GUNICORN_SOCK="/run/gunicorn.sock"
DJANGO_SETTINGS_MODULE="backend"
ALLOWED_HOSTS=None

# Clone the GitHub repository
if [ ! -d "$PROJECT_DIR" ]; then
    git clone $GITHUB_REPO_URL
else
    echo "Directory $PROJECT_DIR already exists. Pulling latest changes."
    cd $PROJECT_DIR
    git pull origin main  # Change 'main' to your default branch if different
fi

# Navigate to project directory
cd $PROJECT_DIR

# Create a virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv $VENV_DIR
fi

# Activate the virtual environment
source $VENV_DIR/bin/activate

# Install required Python packages
pip install -r requirements.txt

# Run database migrations
python manage.py migrate

# Collect static files
python manage.py collectstatic --noinput

# Create system socket for gunicorn
cat <<EOL | sudo tee /etc/systemd/system/gunicorn.socket
[Unit]
Description=gunicorn socket

[Socket]
ListenStream=/run/gunicorn.sock

[Install]
WantedBy=sockets.target
EOL

# Create a Gunicorn systemd service file
cat <<EOL | sudo tee /etc/systemd/system/gunicorn.service
[Unit]
Description=gunicorn daemon for $PROJECT_NAME
Requires=gunicorn.socket
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/gunicorn --access-logfile - --workers 3 --bind unix:$GUNICORN_SOCK $DJANGO_SETTINGS_MODULE.wsgi:application

[Install]
WantedBy=multi-user.target
EOL

# Start and enable Gunicorn service
sudo systemctl start gunicorn
sudo systemctl enable gunicorn

# Set ALLOWED_HOSTS to _ if it's empty or set to "none"
if [ -z "$ALLOWED_HOSTS" ] || [ "$ALLOWED_HOSTS" = "None" ]; then
  ALLOWED_HOSTS="_"
fi

# Create an Nginx server block configuration
cat <<EOL | sudo tee /etc/nginx/sites-available/$PROJECT_NAME
server {
    listen 80 default_server;
    server_name $ALLOWED_HOSTS;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root $PROJECT_DIR;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$GUNICORN_SOCK;
    }
}
EOL

# Enable the Nginx server block
sudo ln -s /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled
sudo nginx -t

# Restart Nginx and gunicorn to apply changes
sudo systemctl restart nginx

sudo service gunicorn restart

sudo service nginx restart


echo "Deployment of $PROJECT_NAME completed successfully!"