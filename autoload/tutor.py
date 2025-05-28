from api_key import get_api_key
from dataclasses import dataclass
from datetime import datetime
from google import genai
from google.genai import types

__all__ = ["VimTutor"]

def create_chat(api_key: str, model: str, contentConfig: types.GenerateContentConfig):
    client = genai.Client(api_key=api_key)
    return client.chats.create(
        model=model,
        config=contentConfig
    )

class VimTutor:
    def __init__(self, api_key: str, system_instruction: str) -> None:
        self.model_name = "gemini-2.0-flash"
        self.selected_index = 0
        self.prompt_count = 0
        self.prompt_token_count = 0
        self.candidates_token_count = 0
        self.history = History()
        config= types.GenerateContentConfig(
            system_instruction=system_instruction,
            response_mime_type='text/plain',
        )
        client = genai.Client(api_key=api_key)
        self.chat = client.chats.create(
            model = self.model_name,
            config = config
        )

    def prompt(self, prompt:str):
        response = self.chat.send_message(prompt)
        self.prompt_count = self.prompt_count + 1
        # Token book keeping.
        promptTokens = 0
        candidatesTokens = 0
        if response.usage_metadata is not None:
            metadata = response.usage_metadata
            promptTokens: int = metadata.prompt_token_count if metadata.prompt_token_count is not None else 0
            candidatesTokens: int = metadata.candidates_token_count if metadata.candidates_token_count is not None else 0
        self.prompt_token_count = self.prompt_token_count + promptTokens
        self.candidates_token_count = self.candidates_token_count + candidatesTokens

        # Fallback if Code ouput failed. Should not happen.
        responseText = ""
        for part in response.candidates[0].content.parts:
            if part.text is not None:
                responseText += part.text
        self.history.add(prompt, responseText, promptTokens, candidatesTokens)
        self.history.truncate(20)
        self.selected_index = len(self.history.entries) - 1
        return self.get_selected()

    def get_total_token_count(self):
        return self.prompt_token_count + self.candidates_token_count

    def get_prompt_token_count(self):
        return self.prompt_token_count

    def get_candidates_token_count(self):
        return self.candidates_token_count

    def get_selected_response(self):
        _, event = self.get_selected()
        if event is not None:
            return event.response

    def get_selected_prompt(self):
        _, event = self.get_selected()
        if event is not None:
            return event.prompt
        return None

    def get_last_response(self):
        event = self.history.get_last_entry()
        if event is not None:
            return event.response
        return None

    def get_last_prompt(self):
        event = self.history.get_last_entry()
        if event is not None:
            return event.prompt
        return None

    def select_previous(self):
        if self.selected_index > 0:
            self.selected_index = self.selected_index - 1
            return self.get_selected()
        return None

    def select_next(self):
        numEntries = len(self.history.entries)
        if self.selected_index < numEntries - 1:
            self.selected_index = self.selected_index + 1
            return self.get_selected()
        return None

    def get_selected(self):
        if len(self.history.entries) == 0:
            return -1, None
        return self.selected_index, self.history.entries[self.selected_index]

@dataclass(frozen=True)
class HistoryEvent:
    prompt: str
    response: str
    prompt_token_count: int
    candidates_token_count: int
    timestamp: float = datetime.now().timestamp()

class History:
    def __init__(self) -> None:
        self.entries: list[HistoryEvent] = []

    def add(self, prompt: str, response: str, promptTokenCount: int, candidatesTokenCount: int):
        self.entries.append(HistoryEvent(prompt, response, promptTokenCount, candidatesTokenCount))

    def get_last_entry(self):
        history_len = len(self.entries)
        return None if history_len == 0 else self.entries[history_len - 1]

    def truncate(self, max_length):
        if len(self.entries) > max_length:
            start_index = len(self.entries) - max_length
            self.entries = self.entries[start_index:]


if __name__ == "__main__":
    api_key = get_api_key()
    if api_key is None:
        print("please provide and api key")
        exit()

    system_instruction = (
        "You are an expert vim tutor."
        "You give clear an concise advise on how to use vim."
        "Your output are vim commands or vimscript function that help the user to edit text with vim."
        "Start with the sequence of commands or the functions and then explain step by step how the user can achieve the declared goal."
        "Format you output in markdown format."
    )

    def print_history_entry(entry):
        print("prompt" + (10 * "-"))
        print(entry.prompt)
        print("response" + (10 * "-"))
        print(entry.response)
        print("tokens" + (10 * "-"))
        print(f"prompt tokens: {entry.prompt_token_count}, candidates tokens: {entry.candidates_token_count}" )
        print(f"total prompts: {agent.prompt_token_count}, total candidates: {agent.candidates_token_count}" )


    agent = VimTutor(api_key, system_instruction)
    prompt = ""
    while prompt is not None:
        prompt = input("# ")
        if prompt == "q":
            prompt = None
            continue
        if prompt == "n":
            entry = agent.select_next()
            if entry is not None:
                print_history_entry(entry)
            continue
        if prompt == "p":
            entry = agent.select_previous()
            if entry is not None:
                print_history_entry(entry)
            continue
        elif prompt != "l":
            agent.prompt(prompt)
        last = agent.history.get_last_entry()
        if last is not None:
            print_history_entry(last)


