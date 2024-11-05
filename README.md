# OpenAI API Client for PostgreSQL

Using the [http extension](https://github.com/pramsey/pgsql-http) for web access, this extension provides utility functions to make it easier to work against the OpenAI API.  The API is avilable from [OpenAI](https://platform.openai.com/docs/overview) of course, but also from other tools like the [Ollama](https://ollama.com) runner for local AI models.

## Uses

The most obvious uses for AI in the database are:

- **Classification and text analysis**. Tie an AI trigger to freeform text fields in your database, so that new data (like reviews and comments) are automatically analyzed and categorized (sentiment analysis for example).
- **Similarity searching.** In conjunction with the [pgvector](https://github.com/pgvector/pgvector) extension, find the "N most similar" items in a corpus. Recommendation engines, for example, can find similar items in a corpus to the one a user is currently looking at.
- **Retrieval-augmented generation.** A combination of basic chatbot technology and similarity searching to improve the results of a natural language AI query by feeding the model with relevant contextual documents before posing a query.

## Setup 

### Using OpenAI

* Set up an [OpenAI API key](https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key)
* Create a working database
* Enable the HTTP extension
  	```sql
  	CREATE EXTENSION http;
  	```
* Set the up the session keys
  	```sql
	SET openai.api_key = 'your_api_key_here';
	SET openai.api_uri = 'https://api.openai.com/v1/';
	SET openai.prompt_model = 'gpt-4o-mini';
	SET openai.embedding_model = 'text-embedding-3-small';
	```
* (Optionally) make the keys persistent
  	```sql
	ALTER DATABASE your_db SET openai.api_key = 'your_api_key_here';
	ALTER DATABASE your_db SET openai.api_uri = 'https://api.openai.com/v1/';
	ALTER DATABASE your_db SET openai.prompt_model = 'gpt-4o-mini';
	ALTER DATABASE your_db SET openai.embedding_model = 'text-embedding-3-small';
	```

### Using Ollama

If you have a workstation with a reasonable amount of memory (16GB or more) you can consider running a mid-sized model locally instead of using OpenAI services.

* [Download Ollama](https://ollama.com) for your workstation

* Verify you can run `ollama` 
	* then `ollama pull llama3.1:latest`
	* and `ollama pull mxbai-embed-large`

* Set the up the session keys
  	```sql
	SET openai.api_uri = 'http://127.0.0.1:11434/v1/';
	SET openai.api_key = 'none';
	SET openai.prompt_model = 'llama3.1:latest';
	SET openai.embedding_model = 'mxbai-embed-large';
	```
* (Optionally) make the keys persistent
  	```sql
	ALTER DATABASE your_db SET openai.api_uri = 'http://127.0.0.1:11434/v1/';
	ALTER DATABASE your_db SET openai.api_key = 'none';
	ALTER DATABASE your_db SET openai.prompt_model = 'llama3.1:latest';
	ALTER DATABASE your_db SET openai.embedding_model = 'mxbai-embed-large';
	```

## Usage

### Functions

- `openai.models()` returns `setof record`. Returns a listing of the AI models available via the API. 
- `openai.prompt(context text, query text, [model text])` returns `text`. Set up context and then pass in a starting prompt for the model.
- `openai.vector(query text, [model text])` returns `text`. For use with embedding models ([Ollama](https://ollama.com/blog/embedding-models), [OpenAI](https://platform.openai.com/docs/guides/embeddings#embedding-models)) only, returns a JSON-formatted float array suitable for direct input into pgvector. Using non-embedding models to generate embeddings will result in extremely poor search results.

### Basic Examples

Read back the settings your database is using.

```sql 
SHOW openai.api_uri;
```
```
       openai.api_uri       
----------------------------
 http://127.0.0.1:11434/v1/
```
List all the models running behind the API you are connecting to. If it is a local API like [Ollama](https://ollama.com/), probably a short list. If it is a hosted API like OpenAI, probably a long one.

```sql
SELECT openai.models();
```
```
SELECT * FROM openai.models();
            id            | object |       created       | owned_by 
--------------------------+--------+---------------------+----------
 mxbai-embed-large:latest | model  | 2024-11-04 20:48:39 | library
 llama3.1:latest          | model  | 2024-07-25 22:45:02 | library
```

Query the model about factual matters. For small models or obscure facts, this may likely return hallucinated results.

```sql
SELECT openai.prompt(
	'You are a very smart physics teacher.',
	'What is the speed of light?'
	);
```
```
A classic question! The speed of light, in a vacuum (a completely 
empty space with no air or matter), is approximately... 
(dramatic pause) ...299,792,458 meters per second!                                +
```

Use the model to summarize a free-form text input. In the extreme, a sentiment analysis prompt can instruct the model to use a fixed set of output tokens, for nice programmatic filtering of free-form inputs.

```sql
SELECT openai.prompt(
  'You are an advanced sentiment analysis model. Read the given 
   feedback text carefully and classify it as one of the 
   following sentiments only: "positive", "neutral", or 
   "negative". Respond with exactly one of these words 
   and no others, using lowercase and no punctuation',
  'I enjoyed the setting and the service and the bisque was 
   great.' );
```
```
  prompt  
----------
 positive
```

Calculate the embedding vector for a given piece of input. Useful for "find the most similar" queries or as an input to [retrieval augmented generation](https://en.wikipedia.org/wiki/Retrieval-augmented_generation) (RAG) systems.

```sql
SELECT openai.vector('A lovely orange pumpkin pie recipe.');
```
```
[-0.021690376, 0.003092674, -0.00023757249, 0.0059805233, 
 0.0024175171, 0.013349159, 0.006348481, 0.016774092, 
 0.0051014116, 0.026803626, 0.015113969, 0.0031985058,
  ... 
 -0.020051343, 0.006571748, 0.008234819, 0.010086719, 
 -0.0071006618, -0.020877795, -0.022467814, 0.010012546, 
 0.0008801813, -0.0006236545, 0.016922941, -0.011781357]
```

## Debugging

To see what's going on inside the functions, set the debug level:

```sql
SET client_min_messages = debug;
```

To work around HTTP timeouts, increase the timeout interval:

```sql
SELECT http_set_curlopt('CURLOPT_TIMEOUT', '10');
```


