curl -fsSO https://elixir-lang.org/install.sh
sh install.sh elixir@1.18.3 otp@27.2.3
installs_dir=$HOME/.elixir-install/installs
export PATH=$installs_dir/otp/27.2.3/bin:$PATH
export PATH=$installs_dir/elixir/1.18.3-otp-27/bin:$PATH
iex
