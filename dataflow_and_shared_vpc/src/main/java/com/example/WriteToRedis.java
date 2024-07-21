package com.example;

import java.io.IOException;

import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.PipelineResult;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.transforms.Create;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.ParDo;
import org.checkerframework.checker.initialization.qual.Initialized;
import org.checkerframework.checker.nullness.qual.NonNull;
import org.checkerframework.checker.nullness.qual.UnknownKeyFor;
import org.apache.beam.sdk.options.ValueProvider;
import redis.clients.jedis.Jedis;

public class WriteToRedis {
    public static void main(String[] args) {
        WriteToRedisOptions options = PipelineOptionsFactory.fromArgs(args)
            .withValidation()
            .as(WriteToRedisOptions.class);
        
        options.setJobName("redis-writer-job");
        
        Pipeline pipeline = Pipeline.create(options);
        
        pipeline.apply(Create.of("hello"))
               .apply(ParDo.of(new WriteToRedisFn(options.getRedisHost(), options.getRedisPort())));
        
        if (options.getTemplateLocation() != null) {
            // We are creating a template
            pipeline.run();
        } else {
            // We are executing the pipeline
            PipelineResult result = pipeline.run();
            
            if (options.getWaitUntilFinish()) {
                result.waitUntilFinish();
            }
        }
    }
    
    static class WriteToRedisFn extends DoFn<String, Void> {
        private final ValueProvider<String> redisHost;
        private final ValueProvider<Integer> redisPort;
        private transient Jedis jedis;

        WriteToRedisFn(ValueProvider<String> redisHost, ValueProvider<Integer> redisPort) {
            this.redisHost = redisHost;
            this.redisPort = redisPort;
        }

        @Setup
        public void setup() {
            jedis = new Jedis(redisHost.get(), redisPort.get());
        }

        @ProcessElement
        public void processElement(ProcessContext c) {
            String value = c.element();
            jedis.set("hello_key", value);
            System.out.println("Wrote '" + value + "' to Redis");
        }

        @Teardown
        public void teardown() {
            if (jedis != null) {
                jedis.close();
            }
        }
    }
}