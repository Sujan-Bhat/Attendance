#!/bin/bash
if [ -f "./antenv/bin/activate" ]; then
    source ./antenv/bin/activate
elif [ -f "../antenv/bin/activate" ]; then
    source ../antenv/bin/activate
fi

# Ensure clean, fully-functional opencv-python-headless is installed with all C extensions
python -c "import cv2; cv2.warpAffine" > /dev/null 2>&1 || {
    echo "Fixing opencv installation..."
    pip uninstall -y opencv-python opencv-python-headless > /dev/null 2>&1 || true
    pip install --no-cache-dir opencv-python-headless==4.12.0.88
}

cd backend
echo "Running database migrations..."
python manage.py migrate
echo "Seeding database..."
python seed.py
echo "Starting Gunicorn server..."
gunicorn attend_backend.wsgi:application --bind=0.0.0.0:8000 --timeout 600

