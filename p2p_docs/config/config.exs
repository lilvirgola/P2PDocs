import Config
# This file is responsible for configuring the P2PDocs application
# it canche the environment specific configuration
# and is loaded before any dependency and is restricted to this project.
Config.import_config("#{Mix.env}.exs")
