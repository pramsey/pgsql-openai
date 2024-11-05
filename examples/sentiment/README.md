# Sentiment Analysis

LLMs have made sentiment analysis almost too ridiculously easy. The main problem is just convincing the model to restrict its summary of the input to a single indicative value, rather than a fully-written-out summary.

For a basic example, imagine a basic feedback form. We get freeform feedback from customers and have the LLM analyze the sentiment in a trigger on INSERT or UPDATE.

```sql
CREATE TABLE feedback (
    feedback text, -- freeform comments from the customer
    sentiment text -- positive/neutral/negative from the LLM
    );
```

The trigger function is just a call into the `openai.prompt()` function with an appropriately restrictive context, to coerce the model into only returning a single word answer.

```sql
--
-- Step 1: Create the trigger function
--
CREATE OR REPLACE FUNCTION analyze_sentiment() RETURNS TRIGGER AS $$
DECLARE
    response TEXT;
BEGIN
    -- Use openai.prompt to classify the sentiment as positive, neutral, or negative
    response := openai.prompt(
        'You are an advanced sentiment analysis model. Read the given feedback text carefully and classify it as one of the following sentiments only: "positive", "neutral", or "negative". Respond with exactly one of these words and no others, using lowercase and no punctuation',
        NEW.feedback
    );

    -- Set the sentiment field based on the model's response
    NEW.sentiment := response;

    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

--
-- Step 2: Create the trigger to execute the function before each INSERT or UPDATE
--
CREATE TRIGGER set_sentiment
    BEFORE INSERT OR UPDATE ON feedback
    FOR EACH ROW
    EXECUTE FUNCTION analyze_sentiment();
```

Once the trigger function is in place, new entries to the feedback form are automatically given a sentiment analysis as they arrive.

```sql
INSERT INTO feedback (feedback) 
    VALUES 
        ('The food was not well cooked and the service was slow.'),
        ('I loved the bisque but the flan was a little too mushy.'),
        ('This was a wonderful dining experience, and I would come again, 
          even though there was a spider in the bathroom.');

SELECT * FROM feedback;
```
```
-[ RECORD 1 ]-----------------------------------------------------
feedback  | The food was not well cooked and the service was slow.
sentiment | negative

-[ RECORD 2 ]-----------------------------------------------------
feedback  | I loved the bisque but the flan was a little too mushy.
sentiment | positive

-[ RECORD 3 ]-----------------------------------------------------
feedback  | This was a wonderful dining experience, and I would 
            come again, even though there was a spider in 
            the bathroom.
sentiment | positive
```

