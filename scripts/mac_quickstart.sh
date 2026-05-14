# Install brew
which -s brew
if [[ $? != 0 ]] ; then
    # Install Homebrew
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    # Add homebrew to PATH: https://stackoverflow.com/a/70006281
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/fritteryerra/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Updating Homebrew"
    brew update
fi
# Install pipenv
brew install pipenv

# Install graphviz (does not work with pipenv)
brew install graphviz

# Install python packages
pipenv install --dev