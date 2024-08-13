"""Chat app with the Dynamics 365 Commerce store assistant."""

import streamlit as st
from airesponsegenerator import AIResponseGenerator

try:

    st.title("""Chat with the Dynamics 365 Commerce store assistant""")

    if "messages" not in st.session_state:
        st.session_state.messages = []
        st.session_state.messages.append(
            {"role": "assistant", "content": "Hello user 👋"})
        st.session_state.messages.append(
            {"role": "assistant", "content": """I am Co-pilot for product discovery.
             Get started by searching for a category of product e.g.shirts,shoes etc 👋"""})

    for message in st.session_state.messages:
        if message["role"] == "assistant":
            with st.chat_message("assistant"):
                st.markdown(message["content"])
        elif message["role"] == "user":
            with st.chat_message("user"):
                st.markdown(message["content"])

    if prompt := st.chat_input(""):
        with st.chat_message("user"):
            st.markdown(prompt)
        st.session_state.messages.append({"role": "user", "content": prompt})

        generator = AIResponseGenerator(st.session_state.messages)
        response = generator.generate()
        if isinstance(response, str):
            with st.chat_message("assistant"):
                st.markdown(response)
            st.session_state.messages.append(
                {"role": "assistant", "content": response})
        elif response is not None:
            for item in response:
                st.session_state.messages.append(item)

            summary = generator.extractsummary()
            with st.chat_message("assistant"):
                st.markdown(summary)
            st.session_state.messages.append(
                {"role": "assistant", "content": summary})

except Exception as e:
    st.error(f"An error occurred: {e}", icon="🚨")
