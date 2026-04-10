// Adaptive Cards Renderer with M365 Theme
// This configuration ensures Adaptive Cards match the app's Microsoft 365 styling

window.adaptiveCardRenderer = {
    // M365-themed Host Configuration
    hostConfig: {
        // Font configuration matching Segoe UI
        fontFamily: "'Segoe UI', -apple-system, BlinkMacSystemFont, 'Roboto', 'Helvetica Neue', sans-serif",

        // Font sizes matching M365 typography
        fontSizes: {
            small: 12,
            default: 14,
            medium: 15,
            large: 18,
            extraLarge: 22
        },

        // Font weights
        fontWeights: {
            lighter: 300,
            default: 400,
            bolder: 600
        },

        // Spacing values
        spacing: {
            small: 8,
            default: 12,
            medium: 16,
            large: 20,
            extraLarge: 28,
            padding: 16
        },

        // Line heights
        lineHeights: {
            small: 16,
            default: 20,
            medium: 22,
            large: 26,
            extraLarge: 30
        },

        // Separator styling
        separator: {
            lineThickness: 1,
            lineColor: "#e5e5e5"
        },

        // Image sizes
        imageSizes: {
            small: 40,
            medium: 80,
            large: 160
        },

        // Container styles matching M365 cards
        containerStyles: {
            default: {
                backgroundColor: "#ffffff",
                foregroundColors: {
                    default: {
                        default: "#242424",
                        subtle: "#616161"
                    },
                    accent: {
                        default: "#5b5fc7",
                        subtle: "#7B83EB"
                    },
                    attention: {
                        default: "#d13438",
                        subtle: "#e74c3c"
                    },
                    good: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    warning: {
                        default: "#ffb900",
                        subtle: "#f39c12"
                    }
                }
            },
            emphasis: {
                backgroundColor: "#f5f5f5",
                foregroundColors: {
                    default: {
                        default: "#242424",
                        subtle: "#616161"
                    },
                    accent: {
                        default: "#5b5fc7",
                        subtle: "#7B83EB"
                    },
                    attention: {
                        default: "#d13438",
                        subtle: "#e74c3c"
                    },
                    good: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    warning: {
                        default: "#ffb900",
                        subtle: "#f39c12"
                    }
                }
            },
            accent: {
                backgroundColor: "#f0f0ff",
                foregroundColors: {
                    default: {
                        default: "#242424",
                        subtle: "#616161"
                    },
                    accent: {
                        default: "#5b5fc7",
                        subtle: "#4a4eb5"
                    },
                    attention: {
                        default: "#d13438",
                        subtle: "#e74c3c"
                    },
                    good: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    warning: {
                        default: "#ffb900",
                        subtle: "#f39c12"
                    }
                }
            },
            good: {
                backgroundColor: "#f0fff0",
                foregroundColors: {
                    default: {
                        default: "#242424",
                        subtle: "#616161"
                    },
                    accent: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    attention: {
                        default: "#d13438",
                        subtle: "#e74c3c"
                    },
                    good: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    warning: {
                        default: "#ffb900",
                        subtle: "#f39c12"
                    }
                }
            },
            attention: {
                backgroundColor: "#fff8e6",
                foregroundColors: {
                    default: {
                        default: "#242424",
                        subtle: "#616161"
                    },
                    accent: {
                        default: "#5b5fc7",
                        subtle: "#7B83EB"
                    },
                    attention: {
                        default: "#d13438",
                        subtle: "#e74c3c"
                    },
                    good: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    warning: {
                        default: "#ffb900",
                        subtle: "#f39c12"
                    }
                }
            },
            warning: {
                backgroundColor: "#fff8e6",
                foregroundColors: {
                    default: {
                        default: "#6b5b35",
                        subtle: "#8a6d3b"
                    },
                    accent: {
                        default: "#5b5fc7",
                        subtle: "#7B83EB"
                    },
                    attention: {
                        default: "#d13438",
                        subtle: "#e74c3c"
                    },
                    good: {
                        default: "#107c10",
                        subtle: "#2ecc71"
                    },
                    warning: {
                        default: "#ffb900",
                        subtle: "#f39c12"
                    }
                }
            }
        },

        // Action button styling
        actions: {
            maxActions: 5,
            spacing: "default",
            buttonSpacing: 8,
            showCard: {
                actionMode: "inline",
                inlineTopMargin: 12
            },
            actionsOrientation: "horizontal",
            actionAlignment: "right"
        },

        // Adaptive card specific settings
        adaptiveCard: {
            allowCustomStyle: true
        },

        // Text block defaults
        textBlock: {
            headingLevel: 2
        },

        // Input styling
        inputs: {
            label: {
                inputSpacing: 8,
                requiredInputs: {
                    weight: "bolder",
                    color: "attention",
                    suffix: " *"
                },
                optionalInputs: {
                    weight: "default",
                    color: "default"
                }
            },
            errorMessage: {
                weight: "default",
                color: "attention"
            }
        }
    },

    // Render function with host config applied
    // UPDATED: Added dotNetRef parameter for instance-based callbacks
    render: function (containerId, cardJson, activityId, dotNetRef) {

        const container = document.getElementById(containerId);
        if (!container) {
            console.error('Adaptive Card container not found:', containerId);
            return;
        }

        // Clear any existing content
        container.innerHTML = '';

        try {
            // Create and configure the Adaptive Card
            const adaptiveCard = new AdaptiveCards.AdaptiveCard();

            // Apply the M365-themed host config
            adaptiveCard.hostConfig = new AdaptiveCards.HostConfig(this.hostConfig);

            // Parse the card JSON
            const cardPayload = typeof cardJson === 'string' ? JSON.parse(cardJson) : cardJson;
            adaptiveCard.parse(cardPayload);

            // Handle action execution
            // UPDATED: Use dotNetRef instance callback instead of static method
            adaptiveCard.onExecuteAction = function (action) {
                if (action instanceof AdaptiveCards.SubmitAction ||
                    action instanceof AdaptiveCards.ExecuteAction) {
                    const data = action.data || {};

                    // Add verb for ExecuteAction if present
                    if (action instanceof AdaptiveCards.ExecuteAction && action.verb) {
                        data.verb = action.verb;
                    }

                    // UPDATED: Call the instance method via DotNetObjectReference
                    // This ensures each card's actions go to the correct Blazor component
                    if (dotNetRef) {
                        dotNetRef.invokeMethodAsync('OnCardActionAsync', data)
                            .catch(err => console.error('Error invoking card action:', err));
                    } else {
                        // Fallback for backwards compatibility (not recommended)
                        console.warn('No dotNetRef provided - using legacy static invocation');
                        DotNet.invokeMethodAsync(
                            "webchatclient",
                            "OnSubmitAsync",
                            data,
                            activityId
                        ).catch(err => console.error('Error invoking submit action:', err));
                    }
                } else if (action instanceof AdaptiveCards.OpenUrlAction) {
                    // Handle URL actions - open in new tab
                    if (action.url) {
                        window.open(action.url, '_blank', 'noopener,noreferrer');
                    }
                }
            };

            // Render the card
            const renderedCard = adaptiveCard.render();

            if (renderedCard) {
                // Add M365 styling class to the rendered card
                renderedCard.classList.add('ac-m365-theme');
                container.appendChild(renderedCard);

                // Apply additional DOM-based styling enhancements
                this.applyM365Enhancements(container);
            }
        } catch (error) {
            console.error('Error rendering Adaptive Card:', error);
            container.innerHTML = '<div class="ac-error">Unable to render card</div>';
        }
    },

    // Apply additional M365 styling enhancements after render
    applyM365Enhancements: function (container) {
        // Add ripple effect to buttons (optional enhancement)
        const buttons = container.querySelectorAll('.ac-pushButton');
        buttons.forEach(button => {
            button.addEventListener('mousedown', function (e) {
                const ripple = document.createElement('span');
                ripple.classList.add('ac-button-ripple');
                this.appendChild(ripple);

                const rect = this.getBoundingClientRect();
                ripple.style.left = (e.clientX - rect.left) + 'px';
                ripple.style.top = (e.clientY - rect.top) + 'px';

                setTimeout(() => ripple.remove(), 600);
            });
        });

        // Enhance inputs with focus states
        const inputs = container.querySelectorAll('.ac-input, .ac-textInput, .ac-choiceSetInput-expanded');
        inputs.forEach(input => {
            input.addEventListener('focus', function () {
                this.closest('.ac-input-container')?.classList.add('ac-input-focused');
            });
            input.addEventListener('blur', function () {
                this.closest('.ac-input-container')?.classList.remove('ac-input-focused');
            });
        });
    }
};