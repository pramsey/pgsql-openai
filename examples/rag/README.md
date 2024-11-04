
# Retrieval-augmented generation

This example shows how to use AI embeddings along with [pgvector](https://github.com/pgvector/pgvector) to produce results of much improved accuracy when working in a narrow information domain, in this case knowledge of Star Trek: The Next Generation (STTNG) episodes.


## Limitations of Models

The `llama3.1:latest` is 4.7Gb in size, and within that envelope it encodes an incredibly large amount of information about the world, but not so much knowledge that it knows the details of STTNG episodes. Which is a shame.

```sql
SELECT openai.prompt(
	'You are a science fiction expert',
	'What is the Star Trek episode where Deanna and her mother are kidnapped?'
	)
```
```
The episode you're referring to is:
**Title:** "Force of Nature"
**Season:** 6
**Episode number:** 25
In this episode, the Enterprise is trapped in an energy-sucking 
plasma vortex that threatens to drag it back in time.
This episode features the main characters: Captain Jean-Luc Picard, 
Commander William Riker, Geordi La Forge, Data, and Worf.
```
This is... a pure halucination. It has some STTNG parts and does list actual characters, but uses a title that never existed, a plot that never happened, and references episode 25 when no season had more than 24 episodes.


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


```

