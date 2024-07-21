package com.example;

import org.apache.beam.sdk.options.Description;
import org.apache.beam.sdk.options.PipelineOptions;
import org.apache.beam.sdk.options.ValueProvider;
import org.apache.beam.runners.dataflow.options.DataflowPipelineOptions;

public interface WriteToRedisOptions extends DataflowPipelineOptions {
    @Description("Redis host")
    ValueProvider<String> getRedisHost();
    void setRedisHost(ValueProvider<String> value);

    @Description("Redis port")
    ValueProvider<Integer> getRedisPort();
    void setRedisPort(ValueProvider<Integer> value);

    @Description("Template location")
    String getTemplateLocation();
    void setTemplateLocation(String value);

    @Description("Wait until finish")
    boolean getWaitUntilFinish();
    void setWaitUntilFinish(boolean value);
}