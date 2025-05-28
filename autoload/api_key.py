import os
import argparse

__all__ = [
    "get_api_key_from_env",
    "get_api_key_from_cmdline_args",
    "get_api_key"
]


def get_api_key_from_env(env_var: str = "GOOGLE_API_KEY"):
    try:
        return os.environ[env_var]
    except KeyError:
        return None


def get_api_key_from_cmdline_args():
    parser = argparse.ArgumentParser(
        'pygen', description='Generate code with Gemini')
    parser.add_argument("-a", "--api_key", help="The Google API key")
    args = parser.parse_args()
    return args.api_key


def get_api_key():
    api_key = get_api_key_from_cmdline_args()
    return api_key if api_key is not None else get_api_key_from_env()


if __name__ == "__main__":
    print(get_api_key())
