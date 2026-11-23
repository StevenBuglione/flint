package com.example.todo;

import java.util.List;
import org.springframework.context.annotation.Scope;
import org.springframework.stereotype.Component;
import picocli.CommandLine.Command;
import picocli.CommandLine.Model.CommandSpec;
import picocli.CommandLine.Option;
import picocli.CommandLine.ParameterException;
import picocli.CommandLine.Parameters;
import picocli.CommandLine.Spec;
import tools.jackson.databind.json.JsonMapper;

@Component
@Command(name = "todo", mixinStandardHelpOptions = true, version = "todo 1.0.0", description = "Keep a to-do list.",
        subcommands = {TodoCommand.Add.class, TodoCommand.ListItems.class, TodoCommand.Done.class,
                TodoCommand.Remove.class})
public class TodoCommand implements Runnable {

    @Spec
    CommandSpec spec;

    @Override
    public void run() {
        throw new ParameterException(spec.commandLine(), "Missing command");
    }

    @Component
    @Scope("prototype")
    @Command(name = "add", mixinStandardHelpOptions = true, description = "Add an item.")
    static class Add implements Runnable {

        private final TodoStore store;
        private final TodoSettings settings;

        @Option(names = {"-p", "--priority"}, description = "low, normal or high (default: default_priority)")
        Priority priority;

        @Parameters(arity = "1..*", paramLabel = "<text>", description = "The text of the item.")
        List<String> text;

        Add(TodoStore store, TodoSettings settings) {
            this.store = store;
            this.settings = settings;
        }

        @Override
        public void run() {
            Priority chosen = priority != null ? priority : settings.defaultPriority();
            System.out.println("added " + store.add(String.join(" ", text), chosen));
        }
    }

    @Component
    @Scope("prototype")
    @Command(name = "list", mixinStandardHelpOptions = true, description = "List open items.")
    static class ListItems implements Runnable {

        private final TodoStore store;
        private final JsonMapper json;

        @Option(names = "--all", description = "Include done items.")
        boolean all;

        @Option(names = "--json", description = "Print a JSON array.")
        boolean asJson;

        ListItems(TodoStore store, JsonMapper json) {
            this.store = store;
            this.json = json;
        }

        @Override
        public void run() {
            List<Item> items = store.items().stream().filter(item -> all || !item.done()).toList();
            if (asJson) {
                System.out.println(json.writeValueAsString(items));
                return;
            }
            for (Item item : items) {
                System.out.printf("%d [%s] %s %s%n", item.id(), item.done() ? "x" : " ", item.priority(), item.text());
            }
        }
    }

    @Component
    @Scope("prototype")
    @Command(name = "done", mixinStandardHelpOptions = true, description = "Mark an item done.")
    static class Done implements Runnable {

        private final TodoStore store;

        @Parameters(paramLabel = "<id>", description = "The item.")
        int id;

        Done(TodoStore store) {
            this.store = store;
        }

        @Override
        public void run() {
            store.done(id);
            System.out.println("done " + id);
        }
    }

    @Component
    @Scope("prototype")
    @Command(name = "remove", mixinStandardHelpOptions = true, description = "Delete an item.")
    static class Remove implements Runnable {

        private final TodoStore store;

        @Parameters(paramLabel = "<id>", description = "The item.")
        int id;

        Remove(TodoStore store) {
            this.store = store;
        }

        @Override
        public void run() {
            store.remove(id);
            System.out.println("removed " + id);
        }
    }
}
