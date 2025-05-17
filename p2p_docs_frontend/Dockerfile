# Use official Node.js image as the base
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy the rest of the application code
COPY . .

# Expose the port the app runs on (change if needed)
EXPOSE 3000

ENV MY_ENV_ENDPOINT="localhost:4000"

# Start the application
CMD ["node", "server.js"]