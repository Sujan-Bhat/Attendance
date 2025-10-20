FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /code

COPY requirements.txt /code/requirements.txt
RUN pip install --upgrade pip
RUN pip install -r /code/requirements.txt

COPY . /code/

EXPOSE 8000

# Add a proper CMD instruction
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "attend_backend.wsgi:application"]
