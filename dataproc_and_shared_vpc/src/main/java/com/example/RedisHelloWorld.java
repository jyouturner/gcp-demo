import redis.clients.jedis.Jedis;

public class RedisHelloWorld {
    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("Usage: RedisHelloWorld <redis_host> <redis_port>");
            System.exit(1);
        }

        String redisHost = args[0];
        int redisPort = Integer.parseInt(args[1]);

        try (Jedis jedis = new Jedis(redisHost, redisPort)) {
            System.out.println("Connecting to Redis");
            String key = "message";
            String value = "Hello from Dataproc!";
            
            jedis.set(key, value);
            System.out.println("Set key: " + key + " to value: " + value);
            
            String retrievedValue = jedis.get(key);
            System.out.println("Retrieved value: " + retrievedValue);
        } catch (Exception e) {
            System.err.println("Error connecting to Redis: " + e.getMessage());
            e.printStackTrace();
        }
    }
}