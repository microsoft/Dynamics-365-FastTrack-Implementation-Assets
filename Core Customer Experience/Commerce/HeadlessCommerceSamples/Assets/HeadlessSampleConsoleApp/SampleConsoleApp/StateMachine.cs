/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace SampleConsoleAppCheckout
{
    using SampleConsoleApp.Common;
    using System;
    using System.Collections.Generic;
    using System.Text;

    public enum Page
    {
        Home,
        Order,
        Search,
        Cart,
        Checkout,
        RequestCancel,
        Terminated
    }

    public enum Action
    {
        Unknown,
        SearchByKeyword,
        AddItemToCart,
        Checkout,
        OrderById,
        RequestCancel,
        Quit
    }

    internal sealed class StateModel
    {
        private readonly Dictionary<StateTransition, Page> transitions;
        private readonly Dictionary<Page, List<Action>> map;
        private readonly Dictionary<string, Action> shortcuts;

        public ILogger Logger { get; set; }

        public StateModel(ILogger logger)
        {
            this.Logger = logger;
            this.CurrentPage = Page.Home;
            this.transitions = new Dictionary<StateTransition, Page>
            {
                { new StateTransition(Page.Home, Action.SearchByKeyword), Page.Search },
                { new StateTransition(Page.Home, Action.AddItemToCart), Page.Cart },
                { new StateTransition(Page.Home, Action.Quit), Page.Terminated },
                { new StateTransition(Page.Home, Action.OrderById), Page.Order },
                { new StateTransition(Page.Home, Action.Unknown), Page.Home },
                

                { new StateTransition(Page.Search, Action.SearchByKeyword), Page.Search },
                { new StateTransition(Page.Search, Action.AddItemToCart), Page.Cart },
                { new StateTransition(Page.Search, Action.Checkout), Page.Cart },
                { new StateTransition(Page.Search, Action.Quit), Page.Terminated },
                { new StateTransition(Page.Search, Action.Unknown), Page.Home },

                { new StateTransition(Page.Cart, Action.SearchByKeyword), Page.Search },
                { new StateTransition(Page.Cart, Action.AddItemToCart), Page.Cart },
                { new StateTransition(Page.Cart, Action.Checkout), Page.Checkout },
                { new StateTransition(Page.Cart, Action.Quit), Page.Terminated },
                { new StateTransition(Page.Cart, Action.Unknown), Page.Home },

                { new StateTransition(Page.Checkout, Action.Quit), Page.Terminated },
                { new StateTransition(Page.Checkout, Action.Unknown), Page.Home },

                { new StateTransition(Page.Order, Action.OrderById), Page.Order },
                { new StateTransition(Page.Order, Action.Quit), Page.Terminated },
                { new StateTransition(Page.Order, Action.Unknown), Page.Home },
                { new StateTransition(Page.Order, Action.RequestCancel), Page.RequestCancel },

                { new StateTransition(Page.RequestCancel, Action.Quit), Page.Terminated },
                { new StateTransition(Page.RequestCancel, Action.Unknown), Page.Home }


            };

            this.map = [];
            this.shortcuts = new Dictionary<string, Action>(StringComparer.OrdinalIgnoreCase);

            var pages = GetEnumList<Page>();
            var actions = GetEnumList<Action>();

            // populate commands per page mappings
            foreach (Page page in pages)
            {
                if (!this.map.ContainsKey(page))
                {
                    this.map[page] = [];
                }

                foreach (Action action in actions)
                {
                    var transition = new StateTransition(page, action);
                    if (this.transitions.TryGetValue(transition, out _))
                    {
                        this.map[page].Add(action);
                    }
                }
            }

            // populate shortcuts
            foreach (Action action in actions)
            {
                string shortcut = action.ToString()[0].ToString();
                this.shortcuts.Add(shortcut, action);
            }
        }

        public Page CurrentPage { get; private set; }

        public Page GetNext(Action action)
        {
            StateTransition transition = new(this.CurrentPage, action);
            if (!transitions.TryGetValue(transition, out Page nextState))
            {
                this.Logger.Error($"> Invalid action. Try again.");
                return this.CurrentPage;
            }

            return nextState;
        }

        public Page MoveNext(Action action)
        {
            this.CurrentPage = this.GetNext(action);
            return this.CurrentPage;
        }

        public string GetActions()
        {
            StringBuilder builder = new();

            this.map.TryGetValue(this.CurrentPage, out List<Action> actions);
            foreach (var action in actions)
            {
                if (action == Action.Unknown)
                {
                    continue;
                }

                char command = action.ToString()[0];
                string text = action.ToString()[1..];

                builder.Append($"[{command}]{text} ");
            }

            return builder.ToString().Trim();
        }

        public Action Convert(string input)
        {
            if (this.shortcuts.TryGetValue(input, out Action action))
            {
                return action;
            }

            return Action.Unknown;
        }

        private static List<T> GetEnumList<T>()
        {
            T[] array = (T[])Enum.GetValues(typeof(T));
            List<T> list = [.. array];
            return list;
        }

        private sealed class StateTransition(Page page, Action action)
        {
            private readonly Page page = page;
            private readonly Action action = action;

            public override int GetHashCode()
            {
                return 17 + 31 * page.GetHashCode() + 31 * action.GetHashCode();
            }

            public override bool Equals(object obj)
            {
                return obj is StateTransition other && this.page == other.page && this.action == other.action;
            }
        }
    }
}