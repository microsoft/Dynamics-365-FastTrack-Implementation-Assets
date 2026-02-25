/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import React from 'react';
import { useState } from 'react';
import { FluentProvider, Button,makeStyles} from '@fluentui/react-components';


const useStyles = makeStyles({
   custombutton: {
    fontSize: '14px', 
    padding: '10px 20px', 
    margin: '5px',
    backgroundColor: '#0078d4', 
    color: 'white'
   }
});

export const Counter = () => {
  const [count, setCount] = useState(0);

  const increment = () => setCount((c) => c + 1);
  const decrement = () => setCount((c) => c - 1);
  const reset = () => setCount(0);
  const styles = useStyles();

  return (
    <FluentProvider>
    <div>
      <h2>Counter: {count}</h2>
      <Button onClick={increment} className={styles.custombutton}>
      Increment
      </Button>
      <Button onClick={decrement} className={styles.custombutton}>
      Decrement
      </Button>
      <Button onClick={reset} className={styles.custombutton}>
      🔁 Reset
      </Button>
    </div>
    </FluentProvider>
  );
}
