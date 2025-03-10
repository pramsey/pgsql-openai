
# Retrieval-augmented generation

This example shows how to use AI embeddings along with [pgvector](https://github.com/pgvector/pgvector) to produce results of much improved accuracy when working in a narrow information domain, in this case knowledge of Star Trek: The Next Generation (STTNG) episodes.


## Limitations of Models

The `llama3.2:latest` is 2.0Gb in size, and within that envelope it encodes an incredibly large amount of information about the world, but not so much knowledge that it knows the details of STTNG episodes. Which is a shame.

```sql
SELECT openai.prompt(
	'You are a science fiction expert',
	'What is the Star Trek episode where Deanna and her mother are kidnapped?'
	);
```
```
I believe you might be thinking of the Star Trek: The Next Generation 
episode "Dark Page", which is Season 5, Episode 9. In this episode, 
Lwaxana Troi (Deanna's mother) visits the Enterprise and plans to 
attend a ceremony on Betazed with her husband. However, she is 
kidnapped by a group of space pirates who want to use her as bait 
to lure her son Jori-Troi back onto their ship.
```

This is... a pure halucination. It is "trekish" but it references an episode that doesn't exist, and characters that don't exist either. We need a way to inject more facts into the LLM process.


## RAG Principles

Our simple prompt of the model failed because the model only had the information encoded in it to work from. There just isn't enough detail about STTNG to get correct summaries, though it can make convincing fake summaries.

RAG stands for "retrieval-augmented generation" but the important word is "augmented"

To get a correct answer, we need to feed the model with a context string that includes useful background information that will inform the result. We want to **augment** our query. Ideally, for the STTNG example, we would do so by adding relevant plot summaries to the query context.

Finding "relevant" augmentation data is pure AI magic. The process works on the idea that any hunk of text can be characterized by a high-dimensionality vector of numbers, called an "**embedding**", and that hunks of text about similar things will have embeddings that are close together in the high-dimensional space.

It is hard to believe this premise is true, and yet when we finish this example, you will see that it is.

So the RAG process is this: 

* Break your background information into blocks of text which form relevant and coherent components, and calculate an embedding for each of those chunks. 
* When you get a query, **before** feeding it into the LLM, first calculate the embedding of the **query**, and use that embedding to find a number of "nearby" chunks from your content database. 
* Now **augment** your query by adding those chunks into the prompt context, and hand the query to the LLM. Assuming the chunks were in fact relevant, the LLM model should do an excellent job of synthesizing them with its background knowledge into a **correct** answer to your query.


## Our Example

To improve our STTNG trivia bot, we will build a chunk database using plot summaries of STTNG episodes. 

```sql
CREATE TABLE tng (
	title text,
	plot text
	);

COPY tng (title, plot) 
	FROM PROGRAM 'curl https://raw.githubusercontent.com/pramsey/pgsql-openai/refs/heads/main/examples/rag/tng.txt'
	WITH (
		FORMAT csv,
		DELIMITER E'\t'
		);
```

Each row of the `tng` table contains a title and episide number slug, and a plot summary for the episode. Unfortunately this data set does not include all 178 episodes.

Next we need to calculate the "embedding" for each rows, using the `openai.vector()` function.

```sql
ALTER TABLE tng
	ADD COLUMN vec vector;

UPDATE tng 
	SET vec = openai.vector(title || ' -- ' || plot)::vector;
```

So, does this "similarity search" work? If we lookup the embedding for our query, and then find the 5 nearest episodes by similarity, does that 5 include the episode we are referencing?

```sql
SELECT title
FROM tng
ORDER BY vec <-> (SELECT openai.vector('What is the Star Trek episode where Deanna and her mother are kidnapped')::vector)
LIMIT 5
```
```
                         title                          
--------------------------------------------------------
 Star Trek: The Next Generation, Ménage à Troi (#3.24)
 Star Trek: The Next Generation, Cost of Living (#5.20)
 Star Trek: The Next Generation, The Loss (#4.10)
 Star Trek: The Next Generation, Manhunt (#2.19)
 Star Trek: The Next Generation, Unification I (#5.7)
```

There it is, and it's even the first entry! [Ménage à Troi](https://en.wikipedia.org/wiki/Ménage_à_Troi) is in fact the edisode where Deanna and her mother are kidnapped (by the Ferengi!) OK, let's automate the whole chain in one function:

* Lookup the embedding vector for the query string.
* Find the 5 closest entries to that vector.
* Pull the plot summaries together into one lump of context.
* Run the query string against the LLM with the context lump.

```sql
CREATE OR REPLACE FUNCTION trektrivia(query_text TEXT) 
	RETURNS TEXT 
	LANGUAGE 'plpgsql' AS $$
DECLARE
    query_embedding VECTOR;
    context_chunks TEXT;
BEGIN
    -- Step 1: Get the embedding vector for the query text
    query_embedding := openai.vector(query_text)::VECTOR;

    -- Step 2: Find the 5 closest plot summaries to the query embedding
    -- Step 3: Lump together results into a context lump
    SELECT string_agg('Episode: { Title: ' || title || ' } Summary: {' || plot, E'}}\n\n\n') INTO context_chunks
    FROM (
        SELECT plot, title
        FROM tng
        ORDER BY vec <-> query_embedding
        LIMIT 5
    ) AS similar_plots;

    -- Step 4: Run the query against the LLM with the augmented context
    RETURN openai.prompt(context_chunks, query_text);
END;
$$;
```

Then run the RAG query and see if we get a better answer!

```sql
SELECT trektrivia('What is the Star Trek episode where Deanna and her mother are kidnapped?');
```
```
 The answer is: Star Trek: The Next Generation - "Menage à Troi" 
 (Season 3, Episode 24)
 In this episode, Counselor Deanna Troi's mother, Lwaxana, 
 is kidnapped by the Ferengi along with Commander William Riker, 
 and they demand that Captain Picard declare his love for 
 Lwaxana in exchange for her safe release.
```
Exactly correct! With the right facts in the context, the LLM was able to compose a coherent and factual answer to the question.


## Conclusion

There is no doubt that using RAG can increase the quality of LLM answers, though as always the answers should be taken with a grain of salt. This example was built with a 9B parameter model running locally, so the extra context made a big difference. Against a frontier model, it probably would not. 

Also, it is still possible to get wrong answers from this RAG system, they just tend to be somewhat less wrong. RAG is not a panacea for eliminating halucination, unfortunately.
