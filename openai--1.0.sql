CREATE SCHEMA IF NOT EXISTS openai;

--
-- Split input text into chunks of a maximum size, to create
-- blocks of content that can be fed into a RAG system. This
-- function is way too primitive to document or publicize, as
-- practical chunking really needs to be tightly tailored to the
-- input document format, to get tight and contextually consistent
-- chunks.
--
CREATE OR REPLACE FUNCTION chunk(input_text text, max_words int default 256)
RETURNS SETOF text
LANGUAGE 'plpgsql'
AS $$
DECLARE
    paragraphs text[];
    paragraph text;
    sentences text[];
    sentence text;
    current_chunk text[] := '{}';  -- Initialize as an empty array of text
    chunk_word_count int := 0;
BEGIN
    -- Split the input text into sentences
    sentences := regexp_split_to_array(replace(input_text,E'\r',''), '[\.\?!]\s+');

    -- Loop through each sentence within the paragraph
    FOREACH sentence IN ARRAY sentences
    LOOP
        -- Calculate the word count for the sentence
        DECLARE
            sentence_word_count int := array_length(regexp_split_to_array(sentence, '\s+'), 1);
            punctuated text;
        BEGIN
            -- Skip empty
            IF NOT sentence ~ '\w' THEN 
                CONTINUE;
            END IF;
            -- Add punctuation back
            IF NOT sentence ~ '\.' THEN
                sentence := sentence || '. ';
                -- RAISE NOTICE '1 %', sentence;
            END IF;
            -- If adding this sentence would exceed the max word limit, return the current chunk
            IF chunk_word_count + sentence_word_count > max_words THEN
                -- Concatenate the array of sentences into a single text string
                RETURN NEXT array_to_string(current_chunk, ' ');

                -- Reset for the next chunk
                current_chunk := '{}';
                chunk_word_count := 0;
            END IF;
            
            -- Add the sentence to the current chunk and update the word count
            current_chunk := current_chunk || sentence;
                            -- RAISE NOTICE '2 %', sentence;

            chunk_word_count := chunk_word_count + sentence_word_count;
        END;
    END LOOP;
        
    -- Return any remaining text as the last chunk
    IF array_length(current_chunk, 1) > 0 THEN
        RETURN NEXT array_to_string(current_chunk, ' ');
    END IF;
END;
$$;

--
-- List all the models being served at the API endpoint
--
CREATE OR REPLACE FUNCTION openai.models()
RETURNS TABLE (
    id text,
    object text,
    created timestamp,
    owned_by text
)
LANGUAGE 'plpgsql'
AS $$
DECLARE
    js jsonb;
    req http_request;
    res http_response;
    api_key text;
    api_uri text;
    uri text;
    model_path text := 'models';
BEGIN
    -- Fetching settings for API key, URI
    api_key := current_setting('openai.api_key', true);
    api_uri := current_setting('openai.api_uri', true);

    IF api_key IS NULL THEN
        RAISE EXCEPTION 'OpenAI: the ''openai.api_key'' is not currently set';
    END IF;

    IF api_uri IS NULL THEN
        RAISE EXCEPTION 'OpenAI: the ''openai.api_uri'' is not currently set';
    END IF;

    uri := api_uri || model_path;
    RAISE DEBUG 'OpenAI: querying %', uri;

    -- Construct the HTTP request and fetch response
    req := (
        'GET',
        uri,
        ARRAY[http_header('Authorization', 'Bearer ' || api_key)],
        NULL,
        NULL
    )::http_request;

    -- Execute the HTTP request
    res := http(req);

    -- Log the response for debugging purposes
    RAISE DEBUG 'OpenAI: Response Status: %', res.status;
    RAISE DEBUG 'OpenAI: Content: %', res.content;

    -- Check if the response status code is not 200
    IF res.status != 200 THEN
        js := res.content::jsonb;
        RAISE EXCEPTION 'OpenAI: request failed with status %, message: %', res.status, js->'error'->>'message';
    END IF;

    -- Parse JSON content from response
    js := res.content::jsonb;

    -- Return query with extracted data from JSON response
    RETURN QUERY
    SELECT
        elem->>'id' AS id,
        elem->>'object' AS object,
        to_timestamp((elem->>'created')::bigint) AT TIME ZONE 'UTC' AS created,
        elem->>'owned_by' AS owned_by
    FROM jsonb_array_elements(js->'data') AS elem;
END;
$$;

--
-- Send a prompt and system context to the LLM for a reponse
--
CREATE OR REPLACE FUNCTION openai.prompt(
    context text, 
    prompt text, 
    model text DEFAULT NULL)
RETURNS text
LANGUAGE 'plpgsql'
AS $$
DECLARE
    js jsonb;
    req http_request;
    res http_response;
    api_key text;
    api_uri text;
    uri text;
    chat_path text := 'chat/completions';
BEGIN

    -- Fetching settings for API key, URI
    api_key := current_setting('openai.api_key', true);
    api_uri := current_setting('openai.api_uri', true);

    IF api_uri IS NULL THEN
        RAISE EXCEPTION 'OpenAI: the ''openai.api_uri'' is not currently set';
    END IF;

    IF api_key IS NULL THEN
        RAISE EXCEPTION 'OpenAI: the ''openai.api_key'' is not currently set';
    END IF;

    -- User-specified model over-rides GUC
    IF model IS NULL THEN
        model := current_setting('openai.prompt_model', true);
    END IF;

    uri := api_uri || chat_path;
    RAISE DEBUG 'OpenAI: querying %', uri;

    -- https://platform.openai.com/docs/guides/text-generation#building-prompts
    js := jsonb_build_object('model', model, 
        'messages', json_build_array(
            jsonb_build_object('role', 'system', 'content', context),
            jsonb_build_object('role', 'user', 'content', prompt)
            )
        );

    RAISE DEBUG 'OpenAI: payload %', js;

    -- Construct the HTTP request and fetch response
    req := (
        'POST',
        uri,
        ARRAY[http_header('Authorization', 'Bearer ' || api_key)],
        'application/json',
        js
    )::http_request;

    -- Execute the HTTP request
    res := http(req);

    -- Log the response for debugging purposes
    RAISE DEBUG 'OpenAI: Response Status: %', res.status;
    RAISE DEBUG 'OpenAI: Content: %', res.content;

    -- Check if the response status code is not 200
    IF res.status != 200 THEN
        js := res.content::jsonb;
        RAISE EXCEPTION 'OpenAI: request failed with status %, message: %', res.status, js->'error'->>'message';
    END IF;

    -- Return query with extracted data from JSON response
    js := res.content::jsonb;
    RETURN js->'choices'->0->'message'->>'content';
END;
$$;

--
-- Get the embedding for a piece of content. Make sure
-- you are using an embedding model with this function.
-- OpenAI will complain if you don't, Ollama will just
-- give you the (very suboptimal) embedding.
--
CREATE OR REPLACE FUNCTION openai.vector(
    input text, 
    model text DEFAULT NULL)
RETURNS text
LANGUAGE 'plpgsql'
AS $$
DECLARE
    js jsonb;
    req http_request;
    res http_response;
    api_key text;
    api_uri text;
    uri text;
    emb_path text := 'embeddings';
    vec text;
BEGIN

    -- Fetching settings for API key, URI
    api_key := current_setting('openai.api_key', true);
    api_uri := current_setting('openai.api_uri', true);

    IF api_uri IS NULL THEN
        RAISE EXCEPTION 'OpenAI: the ''openai.api_uri'' is not currently set';
    END IF;

    IF api_key IS NULL THEN
        RAISE EXCEPTION 'OpenAI: the ''openai.api_key'' is not currently set';
    END IF;

    -- User-specified model over-rides GUC
    IF model IS NULL THEN
        model := current_setting('openai.embedding_model', true);
    END IF;

    uri := api_uri || emb_path;
    RAISE DEBUG 'OpenAI: querying %', uri;

    -- https://platform.openai.com/docs/guides/embeddings
    js := jsonb_build_object(
            'input', input,
            'model', model,
            'encoding_format', 'float' 
            );

    RAISE DEBUG 'OpenAI: payload %', js;

    -- Construct the HTTP request and fetch response
    req := (
        'POST',
        uri,
        ARRAY[http_header('Authorization', 'Bearer ' || api_key)],
        'application/json',
        js
    )::http_request;

    -- Execute the HTTP request
    res := http(req);

    -- Log the response for debugging purposes
    RAISE DEBUG 'OpenAI: Response Status: %', res.status;
    RAISE DEBUG 'OpenAI: Content: %', res.content;

    -- Check if the response status code is not 200
    IF res.status != 200 THEN
        js := res.content::jsonb;
        RAISE EXCEPTION 'OpenAI: request failed with status %, message: %', res.status, js->'error'->>'message';
    END IF;

    -- Return query with extracted data from JSON response
    js := res.content::jsonb;
    vec := js->'data'->0->'embedding';
    RETURN vec;

END;
$$;
