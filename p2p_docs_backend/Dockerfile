FROM elixir:latest

# Set Working Directory
RUN mkdir /app
COPY . /app
WORKDIR /app

# Install dependencies
RUN mix local.hex --force

# Compile the project.
RUN mix do compile

RUN chmod +x ./start.sh
#expose the EPMD port
EXPOSE 4369 9000-9100

EXPOSE 4000

# on startup, run the script
CMD ["./start.sh"]